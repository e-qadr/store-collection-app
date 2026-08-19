const crypto = require("crypto");
const express = require("express");

const ADMIN_ROLES = new Set(["admin"]);
const MANAGED_ROLES = new Set(["collector", "manager", "accountant"]);
const GENERIC_RESET_MESSAGE =
  "إذا كان البريد مرتبطاً بحساب، فسيتم إرسال رسالة لإعادة تعيين كلمة المرور.";
const TEMPORARY_CREDENTIAL_TTL_MS = 24 * 60 * 60 * 1000;
const RECENT_AUTH_MAX_AGE_SECONDS = 5 * 60;

class SlidingWindowRateLimiter {
  constructor({limit, windowMs, now = () => Date.now()}) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.now = now;
    this.entries = new Map();
  }

  take(key) {
    const now = this.now();
    const cutoff = now - this.windowMs;
    const recent = (this.entries.get(key) || []).filter((time) => time > cutoff);
    if (recent.length >= this.limit) {
      this.entries.set(key, recent);
      return false;
    }
    recent.push(now);
    this.entries.set(key, recent);
    return true;
  }
}

function normalizedEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;
}

function validatePassword(password) {
  const value = String(password || "");
  return value.length >= 12 &&
    value.length <= 128 &&
    /[a-z]/.test(value) &&
    /[A-Z]/.test(value) &&
    /\d/.test(value) &&
    /[^A-Za-z0-9]/.test(value);
}

function secureTemporaryPassword(randomBytes = crypto.randomBytes) {
  const categories = [
    "ABCDEFGHJKLMNPQRSTUVWXYZ",
    "abcdefghijkmnopqrstuvwxyz",
    "23456789",
    "!@#$%*-_=+?",
  ];
  const all = categories.join("");
  const bytes = randomBytes(48);
  const characters = categories.map((category, index) =>
    category[bytes[index] % category.length]);
  for (let index = characters.length; index < 20; index += 1) {
    characters.push(all[bytes[index] % all.length]);
  }
  for (let index = characters.length - 1; index > 0; index -= 1) {
    const swapWith = bytes[index + 20] % (index + 1);
    [characters[index], characters[swapWith]] =
      [characters[swapWith], characters[index]];
  }
  return characters.join("");
}

function hashRateLimitKey(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function bearerToken(request) {
  const authorization = request.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1];
}

function timestampFromDate(admin, date) {
  return admin.firestore.Timestamp.fromDate(date);
}

function firebaseErrorCode(error) {
  return String(error?.code || "").replace(/^auth\//, "");
}

function publicError(error) {
  const code = error?.publicCode || firebaseErrorCode(error);
  switch (code) {
    case "email-already-exists":
      return {status: 409, code, message: "تعذر إنشاء الحساب بهذه البيانات."};
    case "user-not-found":
      return {status: 404, code, message: "تعذر العثور على المستخدم المطلوب."};
    case "invalid-argument":
    case "invalid-email":
    case "weak-password":
      return {status: 400, code, message: "البيانات المرسلة غير صالحة."};
    case "forbidden":
      return {status: 403, code, message: "ليست لديك صلاحية لتنفيذ هذه العملية."};
    case "recent-login-required":
      return {status: 401, code, message: "يجب تسجيل الدخول مجدداً قبل تغيير كلمة المرور."};
    case "rate-limited":
      return {status: 429, code, message: "تم تجاوز عدد المحاولات المسموح. حاول لاحقاً."};
    case "configuration-error":
      return {status: 503, code, message: "خدمة إدارة الحسابات غير مهيأة حالياً."};
    default:
      return {status: 500, code: "internal", message: "تعذر إتمام العملية بأمان."};
  }
}

function createPasswordManagementRouter({
  admin,
  firestore,
  firebaseApiKey,
  firebaseEmailLocale = "ar",
  passwordResetContinueUrl,
  fetchImpl = global.fetch,
  now = () => new Date(),
  randomBytes = crypto.randomBytes,
}) {
  const router = express.Router();
  const auth = admin.auth();
  const fieldValue = admin.firestore.FieldValue;
  const adminLimiter = new SlidingWindowRateLimiter({
    limit: 30,
    windowMs: 10 * 60 * 1000,
    now: () => now().getTime(),
  });
  const resetIpLimiter = new SlidingWindowRateLimiter({
    limit: 5,
    windowMs: 15 * 60 * 1000,
    now: () => now().getTime(),
  });
  const resetEmailLimiter = new SlidingWindowRateLimiter({
    limit: 3,
    windowMs: 60 * 60 * 1000,
    now: () => now().getTime(),
  });

  async function sendPasswordResetEmail(email) {
    if (!firebaseApiKey || !fetchImpl) return false;
    const body = {requestType: "PASSWORD_RESET", email};
    if (passwordResetContinueUrl) body.continueUrl = passwordResetContinueUrl;
    try {
      const response = await fetchImpl(
          `https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${encodeURIComponent(firebaseApiKey)}`,
          {
            method: "POST",
            headers: {
              "content-type": "application/json",
              "X-Firebase-Locale": firebaseEmailLocale,
            },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(12000),
          },
      );
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  function auditData({actorUid, targetUid, operation, result, code}) {
    const data = {
      actor_uid: actorUid,
      target_uid: targetUid,
      operation,
      result,
      timestamp: fieldValue.serverTimestamp(),
    };
    if (code) data.result_code = String(code).slice(0, 80);
    return data;
  }

  async function writeAudit(event) {
    await firestore.collection("password_audit_events").add(auditData(event));
  }

  function assignedId(value) {
    const id = String(value || "").trim();
    return id || null;
  }

  function activeManager(profile) {
    return profile?.role === "manager" && profile?.isActive !== false;
  }

  async function prepareManagerAssignment(transaction, {
    branchId,
    managerUid,
    manager,
  }) {
    if (!activeManager(manager)) {
      throw Object.assign(new Error("Invalid manager"), {publicCode: "invalid-argument"});
    }
    const branchReference = firestore.collection("branches").doc(branchId);
    const managerReferences = firestore.collection("branches")
        .where("branch_manager_id", "==", managerUid);
    const [branchSnapshot, currentAssignments] = await Promise.all([
      transaction.get(branchReference),
      transaction.get(managerReferences),
    ]);
    if (!branchSnapshot.exists) {
      throw Object.assign(new Error("Branch missing"), {publicCode: "invalid-argument"});
    }
    const previousManagerUid = assignedId(branchSnapshot.data()?.branch_manager_id);
    const previousManagerSnapshot = previousManagerUid && previousManagerUid !== managerUid ?
      await transaction.get(firestore.collection("users").doc(previousManagerUid)) : null;
    return {
      branchReference,
      branchId,
      managerUid,
      currentAssignments,
      previousManagerSnapshot,
    };
  }

  function applyManagerAssignment(transaction, plan, managerReference, managerWrite, {
    createManager = false,
  } = {}) {
    for (const assignedBranch of plan.currentAssignments.docs) {
      if (assignedBranch.id !== plan.branchId) {
        transaction.update(assignedBranch.ref, {branch_manager_id: null});
      }
    }
    const previousManager = plan.previousManagerSnapshot;
    if (previousManager?.exists &&
        assignedId(previousManager.data()?.branchId) === plan.branchId) {
      transaction.update(previousManager.ref, {branchId: null});
    }
    if (createManager) {
      transaction.set(managerReference, {...managerWrite, branchId: plan.branchId});
    } else {
      transaction.update(managerReference, {...managerWrite, branchId: plan.branchId});
    }
    transaction.update(plan.branchReference, {branch_manager_id: plan.managerUid});
  }

  async function clearManagerReferences(transaction, managerUid) {
    const assignments = await transaction.get(firestore.collection("branches")
        .where("branch_manager_id", "==", managerUid));
    for (const branch of assignments.docs) {
      transaction.update(branch.ref, {branch_manager_id: null});
    }
  }

  async function authenticatedUser(request, _response, next) {
    try {
      const token = bearerToken(request);
      if (!token) throw Object.assign(new Error("Missing token"), {publicCode: "forbidden"});
      const decoded = await auth.verifyIdToken(token, true);
      const snapshot = await firestore.collection("users").doc(decoded.uid).get();
      const profile = snapshot.data();
      if (!snapshot.exists || profile?.isActive === false) {
        throw Object.assign(new Error("Inactive user"), {publicCode: "forbidden"});
      }
      request.authenticatedUser = {decoded, profile};
      next();
    } catch (error) {
      const details = publicError(error);
      _response.status(details.status === 500 ? 401 : details.status).json({
        error: {code: details.code, message: details.message},
      });
    }
  }

  async function requireAdmin(request, response, next) {
    await authenticatedUser(request, response, async () => {
      const {decoded, profile} = request.authenticatedUser;
      if (!ADMIN_ROLES.has(profile.role)) {
        response.status(403).json({
          error: {code: "forbidden", message: "ليست لديك صلاحية لتنفيذ هذه العملية."},
        });
        return;
      }
      if (!adminLimiter.take(decoded.uid)) {
        response.status(429).json({
          error: {code: "rate-limited", message: "تم تجاوز عدد المحاولات المسموح. حاول لاحقاً."},
        });
        return;
      }
      next();
    });
  }

  async function createOrResetResponse(email, temporaryPassword, expiresAt) {
    const emailSent = await sendPasswordResetEmail(email);
    if (emailSent) return {delivery: "email"};
    return {
      delivery: "temporary_password",
      temporaryPassword,
      expiresAt: expiresAt.toISOString(),
    };
  }

  router.post("/auth/forgot-password", async (request, response) => {
    const email = normalizedEmail(request.body?.email);
    const ipKey = hashRateLimitKey(request.ip || request.socket.remoteAddress || "unknown");
    const emailKey = hashRateLimitKey(email);
    const allowed = resetIpLimiter.take(ipKey) && resetEmailLimiter.take(emailKey);
    if (allowed && isEmail(email)) await sendPasswordResetEmail(email);
    response.status(200).json({message: GENERIC_RESET_MESSAGE});
  });

  router.post("/admin/users", requireAdmin, async (request, response) => {
    const actorUid = request.authenticatedUser.decoded.uid;
    const email = normalizedEmail(request.body?.email);
    const name = String(request.body?.name || "").trim();
    const role = String(request.body?.role || "");
    const branchId = assignedId(request.body?.branchId);
    let targetUid = "not-created";
    let createdAuthUser = false;
    try {
      if (!isEmail(email) || name.length < 2 || name.length > 100 ||
          !MANAGED_ROLES.has(role)) {
        throw Object.assign(new Error("Invalid user data"), {publicCode: "invalid-argument"});
      }
      const temporaryPassword = secureTemporaryPassword(randomBytes);
      const issuedAt = now();
      const expiresAt = new Date(issuedAt.getTime() + TEMPORARY_CREDENTIAL_TTL_MS);
      const userRecord = await auth.createUser({
        email,
        password: temporaryPassword,
        displayName: name,
        disabled: false,
        emailVerified: false,
      });
      targetUid = userRecord.uid;
      createdAuthUser = true;
      const userReference = firestore.collection("users").doc(targetUid);
      const userData = {
        uid: targetUid,
        name,
        email,
        role,
        branchId: role === "manager" ? branchId : null,
        createdAt: fieldValue.serverTimestamp(),
        createdBy: actorUid,
        isActive: true,
        mustChangePassword: true,
        passwordState: "temporary",
        passwordVersion: 1,
        credentialIssuedAt: fieldValue.serverTimestamp(),
        temporaryCredentialExpiresAt: timestampFromDate(admin, expiresAt),
      };
      const auditReference = firestore.collection("password_audit_events").doc();
      await firestore.runTransaction(async (transaction) => {
        if (role === "manager" && branchId) {
          const plan = await prepareManagerAssignment(transaction, {
            branchId,
            managerUid: targetUid,
            manager: userData,
          });
          applyManagerAssignment(transaction, plan, userReference, userData, {
            createManager: true,
          });
        } else {
          transaction.set(userReference, userData);
        }
        transaction.set(auditReference, auditData({
          actorUid,
          targetUid,
          operation: "admin_create_user",
          result: "account_created",
        }));
      });
      const delivery = await createOrResetResponse(email, temporaryPassword, expiresAt);
      if (delivery.delivery === "email") {
        const deliveryBatch = firestore.batch();
        deliveryBatch.update(userReference, {passwordState: "email_setup_sent"});
        deliveryBatch.update(auditReference, {result: "success_email"});
        await deliveryBatch.commit().catch(() => {});
      } else {
        await auditReference.update({result: "success_fallback"}).catch(() => {});
      }
      response.status(201).json({user: {uid: targetUid, email}, ...delivery});
    } catch (error) {
      if (createdAuthUser && targetUid !== "not-created") {
        try {
          await auth.deleteUser(targetUid);
        } catch (_) {}
        try {
          await firestore.collection("users").doc(targetUid).delete();
        } catch (_) {}
      }
      try {
        await writeAudit({
          actorUid,
          targetUid,
          operation: "admin_create_user",
          result: "failure",
          code: firebaseErrorCode(error) || error.publicCode,
        });
      } catch (_) {}
      const details = publicError(error);
      response.status(details.status).json({error: {code: details.code, message: details.message}});
    }
  });

  router.post("/admin/users/:uid/reset-password", requireAdmin, async (request, response) => {
    const actorUid = request.authenticatedUser.decoded.uid;
    const targetUid = request.params.uid;
    try {
      if (targetUid === actorUid) {
        throw Object.assign(new Error("Self reset denied"), {publicCode: "forbidden"});
      }
      const targetSnapshot = await firestore.collection("users").doc(targetUid).get();
      const target = targetSnapshot.data();
      if (!targetSnapshot.exists || target?.role === "admin") {
        throw Object.assign(new Error("Target denied"), {publicCode: "forbidden"});
      }
      const userRecord = await auth.getUser(targetUid);
      const temporaryPassword = secureTemporaryPassword(randomBytes);
      const issuedAt = now();
      const expiresAt = new Date(issuedAt.getTime() + TEMPORARY_CREDENTIAL_TTL_MS);
      try {
        const userReference = firestore.collection("users").doc(targetUid);
        const auditReference = firestore.collection("password_audit_events").doc();
        const batch = firestore.batch();
        batch.update(userReference, {
          mustChangePassword: true,
          passwordState: "temporary",
          credentialIssuedAt: fieldValue.serverTimestamp(),
          temporaryCredentialExpiresAt: timestampFromDate(admin, expiresAt),
          passwordVersion: fieldValue.increment(1),
        });
        batch.set(auditReference, auditData({
          actorUid,
          targetUid,
          operation: "admin_reset_password",
          result: "credential_rotated",
        }));
        await batch.commit();
        try {
          await auth.updateUser(targetUid, {password: temporaryPassword});
          await auth.revokeRefreshTokens(targetUid);
        } catch (error) {
          await userReference.update({
            mustChangePassword: target.mustChangePassword ?? false,
            passwordState: target.passwordState || "active",
            passwordVersion: target.passwordVersion || 0,
            credentialIssuedAt: target.credentialIssuedAt || fieldValue.delete(),
            temporaryCredentialExpiresAt:
              target.temporaryCredentialExpiresAt || fieldValue.delete(),
          });
          await auditReference.update({
            result: "failure",
            result_code: firebaseErrorCode(error) || "auth-update-failed",
          }).catch(() => {});
          throw error;
        }
        const delivery = await createOrResetResponse(
            normalizedEmail(userRecord.email || target.email), temporaryPassword, expiresAt);
        if (delivery.delivery === "email") {
          const deliveryBatch = firestore.batch();
          deliveryBatch.update(userReference, {passwordState: "email_setup_sent"});
          deliveryBatch.update(auditReference, {result: "success_email"});
          await deliveryBatch.commit().catch(() => {});
        } else {
          await auditReference.update({result: "success_fallback"}).catch(() => {});
        }
        response.json(delivery);
      } catch (error) {
        throw error;
      }
    } catch (error) {
      try {
        await writeAudit({
          actorUid,
          targetUid,
          operation: "admin_reset_password",
          result: "failure",
          code: firebaseErrorCode(error) || error.publicCode,
        });
      } catch (_) {}
      const details = publicError(error);
      response.status(details.status).json({error: {code: details.code, message: details.message}});
    }
  });

  router.patch("/admin/users/:uid", requireAdmin, async (request, response) => {
    const actorUid = request.authenticatedUser.decoded.uid;
    const targetUid = request.params.uid;
    let target;
    let authenticationStatusChanged = false;
    try {
      if (targetUid === actorUid) {
        throw Object.assign(new Error("Self administration denied"), {publicCode: "forbidden"});
      }
      const targetSnapshot = await firestore.collection("users").doc(targetUid).get();
      target = targetSnapshot.data();
      if (!targetSnapshot.exists || target?.role === "admin") {
        throw Object.assign(new Error("Target denied"), {publicCode: "forbidden"});
      }
      const requestedBranch = request.body?.branchId === undefined ?
        undefined : assignedId(request.body.branchId);
      const updates = {};
      if (request.body?.role !== undefined) {
        const role = String(request.body.role);
        if (!MANAGED_ROLES.has(role)) {
          throw Object.assign(new Error("Invalid role"), {publicCode: "invalid-argument"});
        }
        updates.role = role;
        if (role !== "manager") updates.branchId = null;
      }
      const effectiveRole = updates.role || target.role;
      if (requestedBranch && effectiveRole !== "manager") {
        throw Object.assign(new Error("Only managers may be assigned to a branch"), {
          publicCode: "invalid-argument",
        });
      }
      if (request.body?.isActive !== undefined) {
        if (typeof request.body.isActive !== "boolean") {
          throw Object.assign(new Error("Invalid status"), {publicCode: "invalid-argument"});
        }
        updates.isActive = request.body.isActive;
        await auth.updateUser(targetUid, {disabled: !request.body.isActive});
        authenticationStatusChanged = true;
        if (!request.body.isActive) await auth.revokeRefreshTokens(targetUid);
      }
      if (Object.keys(updates).length === 0 && requestedBranch === undefined) {
        throw Object.assign(new Error("No changes"), {publicCode: "invalid-argument"});
      }
      const targetReference = firestore.collection("users").doc(targetUid);
      await firestore.runTransaction(async (transaction) => {
        const currentSnapshot = await transaction.get(targetReference);
        const current = currentSnapshot.data();
        if (!currentSnapshot.exists || current?.role === "admin") {
          throw Object.assign(new Error("Target denied"), {publicCode: "forbidden"});
        }
        const currentRole = updates.role || current.role;
        const mustDetach = request.body?.isActive === false ||
          currentRole !== "manager" || requestedBranch === null;
        if (requestedBranch && currentRole === "manager") {
          const plan = await prepareManagerAssignment(transaction, {
            branchId: requestedBranch,
            managerUid: targetUid,
            manager: {...current, ...updates, role: currentRole},
          });
          applyManagerAssignment(transaction, plan, targetReference, updates);
        } else {
          if (mustDetach) {
            await clearManagerReferences(transaction, targetUid);
            updates.branchId = null;
          }
          transaction.update(targetReference, updates);
        }
        transaction.set(firestore.collection("password_audit_events").doc(), auditData({
          actorUid, targetUid, operation: "admin_update_user", result: "success",
        }));
      });
      response.json({success: true});
    } catch (error) {
      if (authenticationStatusChanged && target) {
        try {
          await auth.updateUser(targetUid, {
            disabled: target.isActive === false,
          });
        } catch (_) {}
      }
      try {
        await writeAudit({actorUid, targetUid, operation: "admin_update_user", result: "failure", code: error.publicCode});
      } catch (_) {}
      const details = publicError(error);
      response.status(details.status).json({error: {code: details.code, message: details.message}});
    }
  });

  router.post("/admin/branches/:branchId/manager", requireAdmin, async (request, response) => {
    const actorUid = request.authenticatedUser.decoded.uid;
    const branchId = request.params.branchId;
    const managerUid = assignedId(request.body?.managerUid);
    try {
      await firestore.runTransaction(async (transaction) => {
        if (managerUid) {
          const managerReference = firestore.collection("users").doc(managerUid);
          const managerSnapshot = await transaction.get(managerReference);
          const manager = managerSnapshot.data();
          if (!managerSnapshot.exists) {
            throw Object.assign(new Error("Invalid manager"), {publicCode: "invalid-argument"});
          }
          const plan = await prepareManagerAssignment(transaction, {
            branchId,
            managerUid,
            manager,
          });
          applyManagerAssignment(transaction, plan, managerReference, {});
        } else {
          const branchReference = firestore.collection("branches").doc(branchId);
          const branchSnapshot = await transaction.get(branchReference);
          if (!branchSnapshot.exists) {
            throw Object.assign(new Error("Branch missing"), {publicCode: "invalid-argument"});
          }
          const oldManagerUid = assignedId(branchSnapshot.data()?.branch_manager_id);
          const oldManagerSnapshot = oldManagerUid ?
            await transaction.get(firestore.collection("users").doc(oldManagerUid)) : null;
          transaction.update(branchReference, {branch_manager_id: null});
          if (oldManagerSnapshot?.exists &&
              assignedId(oldManagerSnapshot.data()?.branchId) === branchId) {
            transaction.update(oldManagerSnapshot.ref, {branchId: null});
          }
        }
        transaction.set(firestore.collection("password_audit_events").doc(), auditData({
          actorUid,
          targetUid: managerUid || "none",
          operation: "admin_assign_branch_manager",
          result: "success",
        }));
      });
      response.json({success: true});
    } catch (error) {
      try {
        await writeAudit({actorUid, targetUid: managerUid || "none", operation: "admin_assign_branch_manager", result: "failure", code: error.publicCode});
      } catch (_) {}
      const details = publicError(error);
      response.status(details.status).json({error: {code: details.code, message: details.message}});
    }
  });

  router.post("/auth/change-password", authenticatedUser, async (request, response) => {
    const {decoded, profile} = request.authenticatedUser;
    const actorUid = decoded.uid;
    try {
      const authAge = Math.floor(now().getTime() / 1000) - Number(decoded.auth_time || 0);
      if (authAge < 0 || authAge > RECENT_AUTH_MAX_AGE_SECONDS) {
        throw Object.assign(new Error("Stale authentication"), {publicCode: "recent-login-required"});
      }
      const newPassword = String(request.body?.newPassword || "");
      if (!validatePassword(newPassword)) {
        throw Object.assign(new Error("Weak password"), {publicCode: "weak-password"});
      }
      if (profile.mustChangePassword === true && profile.temporaryCredentialExpiresAt) {
        const expiresAt = profile.temporaryCredentialExpiresAt.toDate();
        if (expiresAt.getTime() <= now().getTime()) {
          throw Object.assign(new Error("Expired temporary credential"), {publicCode: "forbidden"});
        }
      }
      if (profile.mustChangePassword === true &&
          profile.passwordState === "temporary_claimed" &&
          decoded.password_setup !== true) {
        throw Object.assign(new Error("Temporary credential was not claimed"), {publicCode: "forbidden"});
      }
      await auth.updateUser(actorUid, {password: newPassword});
      await auth.revokeRefreshTokens(actorUid);
      await firestore.collection("users").doc(actorUid).update({
        mustChangePassword: false,
        passwordState: "active",
        passwordChangedAt: fieldValue.serverTimestamp(),
        temporaryCredentialExpiresAt: fieldValue.delete(),
        credentialIssuedAt: fieldValue.delete(),
        passwordVersion: fieldValue.increment(1),
      });
      await writeAudit({
        actorUid,
        targetUid: actorUid,
        operation: profile.mustChangePassword === true ?
          "complete_required_password_change" : "user_change_password",
        result: "success",
      }).catch(() => {});
      response.json({success: true, signOutRequired: true});
    } catch (error) {
      try {
        await writeAudit({actorUid, targetUid: actorUid, operation: "user_change_password", result: "failure", code: error.publicCode});
      } catch (_) {}
      const details = publicError(error);
      response.status(details.status).json({error: {code: details.code, message: details.message}});
    }
  });

  router.post("/auth/claim-temporary-credential", authenticatedUser, async (request, response) => {
    const {decoded} = request.authenticatedUser;
    const actorUid = decoded.uid;
    const reference = firestore.collection("users").doc(actorUid);
    const claimId = crypto.randomBytes(16).toString("hex");
    try {
      await firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        const profile = snapshot.data();
        if (!snapshot.exists || profile?.mustChangePassword !== true ||
            profile?.passwordState !== "temporary") {
          throw Object.assign(new Error("Credential already claimed"), {publicCode: "forbidden"});
        }
        const expiresAt = profile.temporaryCredentialExpiresAt?.toDate();
        if (!expiresAt || expiresAt.getTime() <= now().getTime()) {
          throw Object.assign(new Error("Expired temporary credential"), {publicCode: "forbidden"});
        }
        transaction.update(reference, {
          passwordState: "temporary_claiming",
          temporaryCredentialClaimId: claimId,
          temporaryCredentialClaimedAt: fieldValue.serverTimestamp(),
        });
      });

      // Rotate the password immediately so the displayed fallback can authenticate
      // only once. The custom token transfers the winning session without exposing
      // the new random value.
      await auth.updateUser(actorUid, {
        password: secureTemporaryPassword(randomBytes),
      });
      const customToken = await auth.createCustomToken(actorUid, {
        password_setup: true,
      });
      await reference.update({
        passwordState: "temporary_claimed",
        temporaryCredentialClaimId: fieldValue.delete(),
      });
      await writeAudit({
        actorUid,
        targetUid: actorUid,
        operation: "claim_temporary_credential",
        result: "success",
      }).catch(() => {});
      response.json({customToken});
    } catch (error) {
      try {
        const snapshot = await reference.get();
        if (snapshot.data()?.temporaryCredentialClaimId === claimId) {
          await reference.update({
            passwordState: "temporary_claim_failed",
            temporaryCredentialClaimId: fieldValue.delete(),
          });
        }
        await writeAudit({
          actorUid,
          targetUid: actorUid,
          operation: "claim_temporary_credential",
          result: "failure",
          code: error.publicCode,
        });
      } catch (_) {}
      const details = publicError(error);
      response.status(details.status).json({error: {code: details.code, message: details.message}});
    }
  });

  router.post("/auth/complete-email-setup", authenticatedUser, async (request, response) => {
    const {decoded, profile} = request.authenticatedUser;
    const actorUid = decoded.uid;
    try {
      const authAge = Math.floor(now().getTime() / 1000) - Number(decoded.auth_time || 0);
      if (authAge < 0 || authAge > RECENT_AUTH_MAX_AGE_SECONDS) {
        throw Object.assign(new Error("Stale authentication"), {publicCode: "recent-login-required"});
      }
      if (profile.mustChangePassword !== true ||
          profile.passwordState !== "email_setup_sent") {
        throw Object.assign(new Error("Email setup is not pending"), {publicCode: "forbidden"});
      }
      const batch = firestore.batch();
      batch.update(firestore.collection("users").doc(actorUid), {
        mustChangePassword: false,
        passwordState: "active",
        passwordChangedAt: fieldValue.serverTimestamp(),
        temporaryCredentialExpiresAt: fieldValue.delete(),
        credentialIssuedAt: fieldValue.delete(),
        passwordVersion: fieldValue.increment(1),
      });
      batch.set(firestore.collection("password_audit_events").doc(), auditData({
        actorUid,
        targetUid: actorUid,
        operation: "complete_email_password_setup",
        result: "success",
      }));
      await batch.commit();
      response.json({success: true});
    } catch (error) {
      await writeAudit({
        actorUid,
        targetUid: actorUid,
        operation: "complete_email_password_setup",
        result: "failure",
        code: error.publicCode,
      }).catch(() => {});
      const details = publicError(error);
      response.status(details.status).json({error: {code: details.code, message: details.message}});
    }
  });

  return router;
}

module.exports = {
  GENERIC_RESET_MESSAGE,
  SlidingWindowRateLimiter,
  createPasswordManagementRouter,
  secureTemporaryPassword,
  validatePassword,
};

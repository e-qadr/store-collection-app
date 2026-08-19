bool isActiveManagerForAssignment(Map<String, dynamic> data) {
  return data['role'] == 'manager' && data['isActive'] != false;
}

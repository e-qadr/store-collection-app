import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> refreshFirestoreQueries(Iterable<Query> queries) async {
  await Future.wait(
    queries.map((query) => query.get(const GetOptions(source: Source.server))),
  );
}

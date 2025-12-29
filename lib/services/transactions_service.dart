import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionsService {
  static CollectionReference<Map<String, dynamic>> txRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions');
  }
}

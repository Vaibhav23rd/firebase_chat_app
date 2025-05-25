import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_chat_app/models/message.dart';
import 'package:firebase_chat_app/models/user.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _generateChatId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Stream<List<Message>> getMessages(String currentUserId, String receiverId) {
    final chatId = _generateChatId(currentUserId, receiverId);
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Message.fromMap(doc.data()))
        .where((msg) =>
    (msg.senderId == currentUserId && msg.receiverId == receiverId) ||
        (msg.senderId == receiverId && msg.receiverId == currentUserId))
        .toList())
        .handleError((error) {
      print('Error in getMessages: $error');
      return [];
    });
  }

  Future<void> initChat(String senderId, String receiverId) async {
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.uid != senderId) {
        throw Exception('Authentication error: Sender ID mismatch (auth: ${authUser?.uid}, sender: $senderId)');
      }

      final chatId = _generateChatId(senderId, receiverId);
      print('Initializing chat: $chatId for sender: $senderId, receiver: $receiverId');

      final senderUserDoc = await _firestore.collection('users').doc(senderId).get();
      final receiverUserDoc = await _firestore.collection('users').doc(receiverId).get();

      if (!senderUserDoc.exists || !receiverUserDoc.exists) {
        throw Exception('User document not found: sender=${senderUserDoc.exists}, receiver=${receiverUserDoc.exists}');
      }

      final senderUser = AppUser.fromMap(senderUserDoc.data()!);
      final receiverUser = AppUser.fromMap(receiverUserDoc.data()!);

      print('Writing to chats/$chatId');
      await _firestore.collection('chats').doc(chatId).set({
        'participants': [senderId, receiverId],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        print('Error writing to chats/$chatId: $e');
        throw e;
      });

      print('Writing to users/$senderId/userChats/$chatId');
      await _firestore.collection('users').doc(senderId).collection('userChats').doc(chatId).set({
        'chatId': chatId,
        'otherParticipantId': receiverId,
        'otherParticipantDisplayName': receiverUser.displayName,
        'lastMessagePreview': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        print('Error writing to users/$senderId/userChats/$chatId: $e');
        throw e;
      });

      print('Writing to users/$receiverId/userChats/$chatId');
      await _firestore.collection('users').doc(receiverId).collection('userChats').doc(chatId).set({
        'chatId': chatId,
        'otherParticipantId': senderId,
        'otherParticipantDisplayName': senderUser.displayName,
        'lastMessagePreview': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        print('Error writing to users/$receiverId/userChats/$chatId: $e');
        throw e;
      });

      print('Chat initialized successfully: $chatId');
    } catch (e) {
      print('Error in initChat: $e');
      rethrow;
    }
  }

  Future<void> sendMessage(String senderId, String receiverId, String text, {String? localImagePath}) async {
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.uid != senderId) {
        throw Exception('Authentication error: Sender ID mismatch (auth: ${authUser?.uid}, sender: $senderId)');
      }

      final chatId = _generateChatId(senderId, receiverId);
      print('Sending message in chat: $chatId, sender: $senderId, receiver: $receiverId, text: $text, image: $localImagePath');

      final message = Message(
        id: const Uuid().v4(),
        senderId: senderId,
        receiverId: receiverId,
        text: text,
        localImagePath: localImagePath,
        createdAt: DateTime.now(),
      );

      final messagePreview = text.isNotEmpty ? text : 'Image';
      final timestamp = FieldValue.serverTimestamp();

      // Update chats collection
      print('Updating chats/$chatId');
      await _firestore.collection('chats').doc(chatId).set({
        'participants': [senderId, receiverId],
        'lastMessage': messagePreview,
        'lastMessageAt': timestamp,
      }, SetOptions(merge: true)).catchError((e) {
        print('Error updating chats/$chatId: $e');
        throw e;
      });

      // Write message to messages subcollection
      print('Writing to chats/$chatId/messages/${message.id}');
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(message.id)
          .set(message.toMap()).catchError((e) {
        print('Error writing to chats/$chatId/messages/${message.id}: $e');
        throw e;
      });

      // Update sender's userChats
      print('Checking users/$senderId/userChats/$chatId');
      final senderChatDoc = await _firestore
          .collection('users')
          .doc(senderId)
          .collection('userChats')
          .doc(chatId)
          .get();
      if (!senderChatDoc.exists) {
        print('Creating users/$senderId/userChats/$chatId');
        final receiverUserDoc = await _firestore.collection('users').doc(receiverId).get();
        if (!receiverUserDoc.exists) {
          throw Exception('Receiver user document not found: $receiverId');
        }
        final receiverUser = AppUser.fromMap(receiverUserDoc.data()!);
        await _firestore.collection('users').doc(senderId).collection('userChats').doc(chatId).set({
          'chatId': chatId,
          'otherParticipantId': receiverId,
          'otherParticipantDisplayName': receiverUser.displayName,
          'lastMessagePreview': messagePreview,
          'lastMessageAt': timestamp,
        }, SetOptions(merge: true)).catchError((e) {
          print('Error creating users/$senderId/userChats/$chatId: $e');
          throw e;
        });
      } else {
        print('Updating users/$senderId/userChats/$chatId');
        await _firestore.collection('users').doc(senderId).collection('userChats').doc(chatId).set({
          'lastMessagePreview': messagePreview,
          'lastMessageAt': timestamp,
        }, SetOptions(merge: true)).catchError((e) {
          print('Error updating users/$senderId/userChats/$chatId: $e');
          throw e;
        });
      }

      // Update receiver's userChats
      print('Checking users/$receiverId/userChats/$chatId');
      final receiverChatDoc = await _firestore
          .collection('users')
          .doc(receiverId)
          .collection('userChats')
          .doc(chatId)
          .get();
      if (!receiverChatDoc.exists) {
        print('Creating users/$receiverId/userChats/$chatId');
        final senderUserDoc = await _firestore.collection('users').doc(senderId).get();
        if (!senderUserDoc.exists) {
          throw Exception('Sender user document not found: $senderId');
        }
        final senderUser = AppUser.fromMap(senderUserDoc.data()!);
        await _firestore.collection('users').doc(receiverId).collection('userChats').doc(chatId).set({
          'chatId': chatId,
          'otherParticipantId': senderId,
          'otherParticipantDisplayName': senderUser.displayName,
          'lastMessagePreview': messagePreview,
          'lastMessageAt': timestamp,
        }, SetOptions(merge: true)).catchError((e) {
          print('Error creating users/$receiverId/userChats/$chatId: $e');
          throw e;
        });
      } else {
        print('Updating users/$receiverId/userChats/$chatId');
        await _firestore.collection('users').doc(receiverId).collection('userChats').doc(chatId).set({
          'lastMessagePreview': messagePreview,
          'lastMessageAt': timestamp,
        }, SetOptions(merge: true)).catchError((e) {
          print('Error updating users/$receiverId/userChats/$chatId: $e');
          throw e;
        });
      }

      print('Message sent successfully in chat: $chatId');
    } catch (e) {
      print('Error in sendMessage: $e');
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> getUserChats(String userId) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null || authUser.uid != userId) {
      print('Error in getUserChats: User not authenticated or ID mismatch (auth: ${authUser?.uid}, input: $userId)');
      throw Exception('User not authenticated or ID mismatch');
    }
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats')
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) {
      print('getUserChats snapshot: ${snapshot.docs.length} chats found for user $userId');
      return snapshot.docs.map((doc) => doc.data()).toList();
    }).handleError((error) {
      print('Error in getUserChats: $error');
      throw error;
    });
  }
}
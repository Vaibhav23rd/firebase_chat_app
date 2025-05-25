import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_chat_app/models/user.dart';
import 'package:firebase_chat_app/services/auth_service.dart';
import 'package:firebase_chat_app/services/chat_service.dart';
import 'package:firebase_chat_app/utils/locator.dart';
import 'package:firebase_chat_app/screens/chat_screen.dart';
import 'package:firebase_chat_app/screens/login_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppUser currentUser;

  const HomeScreen({super.key, required this.currentUser});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _chatService = locator<ChatService>();
  final _authService = locator<AuthService>();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final authUser = FirebaseAuth.instance.currentUser;
    print('HomeScreen init: widget.currentUser.id=${widget.currentUser.id}, authUser.uid=${authUser?.uid}');
    if (authUser == null || authUser.uid != widget.currentUser.id) {
      Fluttertoast.showToast(
        msg: 'Authentication error: User ID mismatch',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      _authService.signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _showFindDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Find'),
        content: TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Receiver Email',
            hintText: 'Enter email to chat with',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = _emailController.text.trim();
              if (email.isEmpty) {
                Fluttertoast.showToast(
                  msg: 'Please enter an email',
                  toastLength: Toast.LENGTH_LONG,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                );
                return;
              }
              try {
                print('Querying users for email: $email');
                final query = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: email)
                    .limit(1)
                    .get();
                if (query.docs.isEmpty) {
                  Fluttertoast.showToast(
                    msg: 'User not found',
                    toastLength: Toast.LENGTH_LONG,
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.red,
                    textColor: Colors.white,
                  );
                  return;
                }
                final receiver = AppUser.fromMap(query.docs.first.data());
                print('Found receiver: id=${receiver.id}, displayName=${receiver.displayName}');
                if (receiver.id == widget.currentUser.id) {
                  Fluttertoast.showToast(
                    msg: 'Cannot chat with yourself',
                    toastLength: Toast.LENGTH_LONG,
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.red,
                    textColor: Colors.white,
                  );
                  return;
                }
                print('Calling initChat for sender: ${widget.currentUser.id}, receiver: ${receiver.id}');
                await _chatService.initChat(widget.currentUser.id, receiver.id);
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      currentUser: widget.currentUser,
                      receiver: receiver,
                    ),
                  ),
                );
              } catch (e) {
                print('Error finding user: $e');
                Fluttertoast.showToast(
                  msg: 'Error finding user: $e',
                  toastLength: Toast.LENGTH_LONG,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                );
              }
            },
            child: const Text('Find'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showFindDialog,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatService.getUserChats(widget.currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print('StreamBuilder error: ${snapshot.error}');
            return Center(child: Text('Error loading chats: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            print('StreamBuilder waiting for user ${widget.currentUser.id}');
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            print('No chats found for user ${widget.currentUser.id}');
            return const Center(child: Text('No Messages'));
          }
          final userChats = snapshot.data!;
          print('Found ${userChats.length} chats for user ${widget.currentUser.id}');

          return ListView.builder(
            itemCount: userChats.length,
            itemBuilder: (context, index) {
              final chatData = userChats[index];
              final receiverId = chatData['otherParticipantId'] as String;
              final receiverDisplayName = chatData['otherParticipantDisplayName'] as String? ?? 'Unknown';
              final lastMessagePreview = chatData['lastMessagePreview'] as String? ?? '';
              final chatId = chatData['chatId'] as String;

              return ListTile(
                leading: CircleAvatar(
                  child: Text(receiverDisplayName.isNotEmpty ? receiverDisplayName[0].toUpperCase() : '?'),
                ),
                title: Text(receiverDisplayName),
                subtitle: Text(lastMessagePreview),
                onTap: () async {
                  try {
                    final receiverDoc = await FirebaseFirestore.instance.collection('users').doc(receiverId).get();
                    if (!receiverDoc.exists) {
                      Fluttertoast.showToast(
                        msg: 'User not found',
                        toastLength: Toast.LENGTH_LONG,
                        gravity: ToastGravity.BOTTOM,
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
                      );
                      return;
                    }
                    final receiver = AppUser.fromMap(receiverDoc.data()!);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          currentUser: widget.currentUser,
                          receiver: receiver,
                        ),
                      ),
                    );
                  } catch (e) {
                    print('Error loading receiver: $e');
                    Fluttertoast.showToast(
                      msg: 'Error loading chat: $e',
                      toastLength: Toast.LENGTH_LONG,
                      gravity: ToastGravity.BOTTOM,
                      backgroundColor: Colors.red,
                      textColor: Colors.white,
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
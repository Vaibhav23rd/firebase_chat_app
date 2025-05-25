import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_chat_app/models/user.dart';
import 'package:firebase_chat_app/models/message.dart';
import 'package:firebase_chat_app/services/chat_service.dart';
import 'package:firebase_chat_app/utils/locator.dart';
import 'dart:io';

class ChatScreen extends StatefulWidget {
  final AppUser currentUser;
  final AppUser receiver;

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.receiver,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = locator<ChatService>();
  final ImagePicker _picker = ImagePicker();

  List<ChatMessage> _messages = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.receiver.displayName)),
      body: StreamBuilder<List<Message>>(
        stream: _chatService.getMessages(widget.currentUser.id, widget.receiver.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print('StreamBuilder error: ${snapshot.error}');
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            print('StreamBuilder waiting for messages');
            return const Center(child: CircularProgressIndicator());
          }
          final messages = snapshot.data ?? [];
          _messages = messages
              .map((msg) => ChatMessage(
            text: msg.text,
            user: ChatUser(
              id: msg.senderId,
              firstName: msg.senderId == widget.currentUser.id
                  ? widget.currentUser.displayName
                  : widget.receiver.displayName,
            ),
            createdAt: msg.createdAt,
            medias: msg.localImagePath != null
                ? [
              ChatMedia(
                url: msg.localImagePath!,
                type: MediaType.image,
                fileName: path.basename(msg.localImagePath!),
              )
            ]
                : [],
          ))
              .toList();

          return DashChat(
            currentUser: ChatUser(
              id: widget.currentUser.id,
              firstName: widget.currentUser.displayName,
            ),
            onSend: _sendMessage,
            messages: _messages,
            inputOptions: InputOptions(
              trailing: [
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: _pickImage,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendMessage(ChatMessage chatMessage) async {
    try {
      print('Sending message: text=${chatMessage.text}, sender=${widget.currentUser.id}, receiver=${widget.receiver.id}');
      await _chatService.sendMessage(
        widget.currentUser.id,
        widget.receiver.id,
        chatMessage.text,
      );
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      print('Picking image for sender: ${widget.currentUser.id}');
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = path.basename(pickedFile.path);
        final savedImage = await File(pickedFile.path).copy('${directory.path}/$fileName');
        print('Sending image: path=${savedImage.path}');
        await _chatService.sendMessage(
          widget.currentUser.id,
          widget.receiver.id,
          '',
          localImagePath: savedImage.path,
        );
        Fluttertoast.showToast(
          msg: 'Image sent',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      print('Error sending image: $e');
      Fluttertoast.showToast(
        msg: 'Error sending image: $e',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }
}
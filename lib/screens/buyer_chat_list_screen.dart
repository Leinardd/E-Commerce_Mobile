import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_room.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_conversation_screen.dart';

class BuyerChatListScreen extends StatefulWidget {
  const BuyerChatListScreen({super.key});

  @override
  State<BuyerChatListScreen> createState() => _BuyerChatListScreenState();
}

class _BuyerChatListScreenState extends State<BuyerChatListScreen> {
  String? _email;

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final email = await AuthService.getUserEmail();
    if (mounted) setState(() => _email = email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _email == null
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF0A0A0A)),
                ),
              ),
            )
          : _buildList(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      title: Text(
        'MESSAGES',
        style: GoogleFonts.commissioner(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
          color: const Color(0xFF0A0A0A),
        ),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xFFEEEEEE)),
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<List<ChatRoom>>(
      stream: ChatService().watchBuyerRooms(_email!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Color(0xFF0A0A0A)),
              ),
            ),
          );
        }

        final rooms = snapshot.data ?? [];

        if (rooms.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chat_bubble_outline,
                    size: 40, color: Color(0xFFDDDDDD)),
                const SizedBox(height: 16),
                Text(
                  'NO MESSAGES YET',
                  style: GoogleFonts.commissioner(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: const Color(0xFFBBBBBB),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap "Message Seller" on a product\nto start a conversation.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFFBBBBBB),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: rooms.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
          itemBuilder: (ctx, i) => _RoomTile(
            room: rooms[i],
            currentEmail: _email!,
            currentRole: 'buyer',
          ),
        );
      },
    );
  }
}

// ── Room tile ─────────────────────────────────────────────────────────────────

class _RoomTile extends StatelessWidget {
  final ChatRoom room;
  final String currentEmail;
  final String currentRole;

  const _RoomTile({
    required this.room,
    required this.currentEmail,
    required this.currentRole,
  });

  @override
  Widget build(BuildContext context) {
    final unread = room.unreadCountFor(currentRole);
    final isUnread = unread > 0;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatConversationScreen(
            room: room,
            currentEmail: currentEmail,
            currentRole: currentRole,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFF0F0F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.storefront_outlined,
                size: 20,
                color: Color(0xFF888888),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.sellerName.isNotEmpty
                        ? room.sellerName.toUpperCase()
                        : room.sellerEmail,
                    style: GoogleFonts.commissioner(
                      fontSize: 10,
                      fontWeight: isUnread
                          ? FontWeight.w700
                          : FontWeight.w600,
                      letterSpacing: 1.5,
                      color: const Color(0xFF0A0A0A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    room.lastMessage.isNotEmpty
                        ? room.lastMessage
                        : 'No messages yet',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isUnread
                          ? const Color(0xFF0A0A0A)
                          : const Color(0xFFAAAAAA),
                      fontWeight: isUnread
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Time + unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime(room.lastMessageAt),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: const Color(0xFFBBBBBB),
                  ),
                ),
                if (isUnread) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0A0A0A),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m${dt.hour >= 12 ? 'PM' : 'AM'}';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

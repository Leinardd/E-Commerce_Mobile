import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/chat_room.dart';
import '../../services/chat_service.dart';
import '../../services/seller_auth_service.dart';
import '../chat_conversation_screen.dart';

class SellerChatInboxScreen extends StatefulWidget {
  const SellerChatInboxScreen({super.key});

  @override
  State<SellerChatInboxScreen> createState() => _SellerChatInboxScreenState();
}

class _SellerChatInboxScreenState extends State<SellerChatInboxScreen>
    with SingleTickerProviderStateMixin {
  String? _email;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadEmail();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmail() async {
    final email = await SellerAuthService.getCurrentSellerEmail();
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
          : _buildTabBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF0A0A0A), size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        'CHAT INBOX',
        style: GoogleFonts.commissioner(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
          color: const Color(0xFF0A0A0A),
        ),
      ),
      bottom: TabBar(
        controller: _tabCtrl,
        labelColor: const Color(0xFF0A0A0A),
        unselectedLabelColor: const Color(0xFFAAAAAA),
        indicatorColor: const Color(0xFF0A0A0A),
        indicatorWeight: 1.5,
        labelStyle: GoogleFonts.commissioner(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
        unselectedLabelStyle: GoogleFonts.commissioner(
          fontSize: 9,
          fontWeight: FontWeight.w400,
          letterSpacing: 2,
        ),
        tabs: const [Tab(text: 'OPEN'), Tab(text: 'RESOLVED')],
      ),
    );
  }

  Widget _buildTabBody() {
    return StreamBuilder<List<ChatRoom>>(
      stream: ChatService().watchSellerRooms(_email!),
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

        final all = snapshot.data ?? [];
        final open = all.where((r) => !r.isResolved).toList();
        final resolved = all.where((r) => r.isResolved).toList();

        return TabBarView(
          controller: _tabCtrl,
          children: [
            _RoomList(
              rooms: open,
              currentEmail: _email!,
              emptyLabel: 'NO OPEN CHATS',
              emptyHint: 'New buyer messages will appear here.',
            ),
            _RoomList(
              rooms: resolved,
              currentEmail: _email!,
              emptyLabel: 'NO RESOLVED CHATS',
              emptyHint: 'Resolved conversations will appear here.',
            ),
          ],
        );
      },
    );
  }
}

// ── Room list ──────────────────────────────────────────────────────────────────

class _RoomList extends StatelessWidget {
  final List<ChatRoom> rooms;
  final String currentEmail;
  final String emptyLabel;
  final String emptyHint;

  const _RoomList({
    required this.rooms,
    required this.currentEmail,
    required this.emptyLabel,
    required this.emptyHint,
  });

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined,
                size: 40, color: Color(0xFFDDDDDD)),
            const SizedBox(height: 16),
            Text(
              emptyLabel,
              style: GoogleFonts.commissioner(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: const Color(0xFFBBBBBB),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              emptyHint,
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
      itemBuilder: (ctx, i) => _SellerRoomTile(
        room: rooms[i],
        currentEmail: currentEmail,
      ),
    );
  }
}

// ── Seller room tile ──────────────────────────────────────────────────────────

class _SellerRoomTile extends StatelessWidget {
  final ChatRoom room;
  final String currentEmail;

  const _SellerRoomTile({required this.room, required this.currentEmail});

  @override
  Widget build(BuildContext context) {
    final unread = room.sellerUnreadCount;
    final isUnread = unread > 0;
    final buyerLabel = room.buyerName.isNotEmpty
        ? room.buyerName.toUpperCase()
        : room.buyerEmail;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatConversationScreen(
            room: room,
            currentEmail: currentEmail,
            currentRole: 'seller',
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
                Icons.person_outline,
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
                    buyerLabel,
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
            // Time + badge
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

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';
import '../models/product.dart';
import '../services/chat_service.dart';

class ChatConversationScreen extends StatefulWidget {
  final ChatRoom room;
  final String currentEmail;
  final String currentRole; // 'buyer' | 'seller'
  final bool productJustShared;

  const ChatConversationScreen({
    super.key,
    required this.room,
    required this.currentEmail,
    required this.currentRole,
    this.productJustShared = false,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _chat = ChatService();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _newMessageSub;
  bool _loadingHistory = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _isSending = false;
  bool _partnerIsTyping = false;
  Timer? _typingTimer;
  bool _isSelfTyping = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _subscribeRealtime();
    _markRead();
  }

  @override
  void dispose() {
    _newMessageSub?.cancel();
    _chat.unsubscribeTyping();
    _typingTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final msgs = await _chat.fetchMessages(widget.room.id);
    if (!mounted) return;
    setState(() {
      // fetchMessages returns newest-first; reverse for display
      _messages.addAll(msgs.reversed);
      _hasMore = msgs.length == 40;
      _loadingHistory = false;
    });
    _scrollToBottom();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    final older = await _chat.fetchMessages(
      widget.room.id,
      beforeId: _messages.first.id,
    );
    if (!mounted) return;
    setState(() {
      _messages.insertAll(0, older.reversed);
      _hasMore = older.length == 40;
      _loadingMore = false;
    });
  }

  void _subscribeRealtime() {
    _newMessageSub = _chat.watchNewMessages(widget.room.id).listen((msg) {
      if (!mounted) return;
      // Avoid duplicate if we optimistically added the message
      if (_messages.any((m) => m.id == msg.id)) return;
      setState(() => _messages.add(msg));
      _scrollToBottom();
      if (msg.senderEmail != widget.currentEmail) {
        _markRead();
      }
    });

    _chat.subscribeTyping(
      roomId: widget.room.id,
      onTyping: (email, isTyping) {
        if (!mounted || email == widget.currentEmail) return;
        setState(() => _partnerIsTyping = isTyping);
      },
    );
  }

  void _markRead() {
    _chat.markMessagesRead(widget.room.id, widget.currentRole);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String value) {
    final isTyping = value.isNotEmpty;
    if (isTyping != _isSelfTyping) {
      _isSelfTyping = isTyping;
      _chat.sendTyping(
        roomId: widget.room.id,
        senderEmail: widget.currentEmail,
        isTyping: isTyping,
      );
    }
    // Auto-clear typing after 3 seconds of inactivity
    if (isTyping) {
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _isSelfTyping = false;
        _chat.sendTyping(
          roomId: widget.room.id,
          senderEmail: widget.currentEmail,
          isTyping: false,
        );
      });
    }
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    _textCtrl.clear();
    _isSelfTyping = false;
    _chat.sendTyping(
        roomId: widget.room.id,
        senderEmail: widget.currentEmail,
        isTyping: false);
    setState(() => _isSending = true);
    await _chat.sendTextMessage(
      roomId: widget.room.id,
      senderEmail: widget.currentEmail,
      senderRole: widget.currentRole,
      content: text,
    );
    setState(() => _isSending = false);
    _scrollToBottom();
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    setState(() => _isSending = true);
    await _chat.sendImageMessage(
      roomId: widget.room.id,
      senderEmail: widget.currentEmail,
      senderRole: widget.currentRole,
      imageFile: File(picked.path),
    );
    setState(() => _isSending = false);
    _scrollToBottom();
  }

  String get _partnerName {
    if (widget.currentRole == 'buyer') return widget.room.sellerName;
    return widget.room.buyerName.isNotEmpty
        ? widget.room.buyerName
        : widget.room.buyerEmail;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          if (_partnerIsTyping) _TypingIndicator(name: _partnerName),
          _buildInputBar(),
        ],
      ),
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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _partnerName.toUpperCase(),
            style: GoogleFonts.commissioner(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: const Color(0xFF0A0A0A),
            ),
          ),
          if (widget.room.isResolved)
            Text(
              'RESOLVED',
              style: GoogleFonts.commissioner(
                fontSize: 8,
                letterSpacing: 1.5,
                color: const Color(0xFF999999),
              ),
            ),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xFFEEEEEE)),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_loadingHistory) {
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

    final items = _effectiveMessages;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification &&
            _scrollCtrl.position.pixels == 0) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (_loadingMore && i == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(Color(0xFFAAAAAA)),
                  ),
                ),
              ),
            );
          }
          final idx = _loadingMore ? i - 1 : i;
          final msg = items[idx];
          final showDate = idx == 0 ||
              !_sameDay(items[idx - 1].createdAt, msg.createdAt);
          return Column(
            children: [
              if (showDate) _DateDivider(date: msg.createdAt),
              if (msg.isSystem)
                _SystemMessageBubble(message: msg)
              else
                _MessageBubble(
                  message: msg,
                  isMine: msg.senderEmail == widget.currentEmail,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Image picker
            GestureDetector(
              onTap: _isSending ? null : _pickAndSendImage,
              child: Icon(
                Icons.image_outlined,
                size: 22,
                color: _isSending
                    ? const Color(0xFFCCCCCC)
                    : const Color(0xFF666666),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                focusNode: _focusNode,
                onChanged: _onTextChanged,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF0A0A0A),
                ),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFFBBBBBB),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFF0A0A0A)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _isSending ? null : _send,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _isSending
                      ? const Color(0xFFCCCCCC)
                      : const Color(0xFF0A0A0A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // True once the seller has sent at least one real reply.
  bool get _hasSellerReply =>
      _messages.any((m) => m.senderRole == 'seller');

  // Local-only welcome message shown until the seller first replies.
  ChatMessage get _welcomeMessage => ChatMessage(
        id: '__system_welcome__',
        roomId: widget.room.id,
        senderEmail: 'system',
        senderRole: 'system',
        content:
            'Hi! Thanks for reaching out to $_partnerName. '
            'Your message has been sent and they\'ll reply shortly. '
            'Feel free to ask any questions about the product!',
        messageType: 'system',
        isRead: true,
        createdAt: DateTime.now(),
      );

  // Messages to display — appends the client-side welcome when no seller
  // reply exists yet, OR whenever a product was just shared.
  List<ChatMessage> get _effectiveMessages {
    if (_loadingHistory) return _messages;
    if (!_hasSellerReply || widget.productJustShared) {
      return [..._messages, _welcomeMessage];
    }
    return _messages;
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                _buildContent(context),
                const SizedBox(height: 3),
                _buildMeta(),
              ],
            ),
          ),
          if (isMine) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (message.isImage && message.imageUrl != null) {
      return _ImageBubble(url: message.imageUrl!, isMine: isMine);
    }
    if (message.isProduct) {
      return _ProductBubble(message: message, isMine: isMine);
    }
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? const Color(0xFF0A0A0A) : const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
      ),
      child: Text(
        message.content,
        style: GoogleFonts.inter(
          fontSize: 14,
          color: isMine ? Colors.white : const Color(0xFF0A0A0A),
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildMeta() {
    final time = _formatTime(message.createdAt);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: const Color(0xFFBBBBBB),
          ),
        ),
        if (isMine) ...[
          const SizedBox(width: 4),
          Icon(
            message.isRead ? Icons.done_all : Icons.done,
            size: 12,
            color: message.isRead
                ? const Color(0xFF0A0A0A)
                : const Color(0xFFBBBBBB),
          ),
        ],
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}

// ── System message bubble ─────────────────────────────────────────────────────

class _SystemMessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _SystemMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFEEEEEE))),
          const SizedBox(width: 10),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.70,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD6E0FF), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4A6CF7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VARÓN SUPPORT',
                        style: GoogleFonts.commissioner(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: const Color(0xFF4A6CF7),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        message.content,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF3A4A7A),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(message.createdAt),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: const Color(0xFF8FA3C8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: Color(0xFFEEEEEE))),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }
}

// ── Image bubble ──────────────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  final String url;
  final bool isMine;
  const _ImageBubble({required this.url, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 200,
          height: 200,
          color: const Color(0xFFF0F0F0),
          child: const Icon(Icons.broken_image_outlined,
              color: Color(0xFFCCCCCC)),
        ),
      ),
    );
  }
}

// ── Product reference bubble ──────────────────────────────────────────────────

class _ProductBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  const _ProductBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: isMine ? const Color(0xFF0A0A0A) : const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.productImageUrl != null &&
              message.productImageUrl!.isNotEmpty)
            Image.network(
              message.productImageUrl!,
              width: 220,
              height: 140,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 140,
                color: const Color(0xFFE0E0E0),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.productName ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        isMine ? Colors.white : const Color(0xFF0A0A0A),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (message.productPrice != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '₱${message.productPrice!.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isMine
                          ? const Color(0xFFCCCCCC)
                          : const Color(0xFF666666),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Date divider ──────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFEEEEEE))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _label(date),
              style: GoogleFonts.commissioner(
                fontSize: 9,
                letterSpacing: 1.5,
                color: const Color(0xFFBBBBBB),
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFEEEEEE))),
        ],
      ),
    );
  }

  String _label(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'TODAY';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year &&
        d.month == yesterday.month &&
        d.day == yesterday.day) {
      return 'YESTERDAY';
    }
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final String name;
  const _TypingIndicator({required this.name});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 4),
      child: Row(
        children: [
          FadeTransition(
            opacity: _anim,
            child: Text(
              '${widget.name} is typing...',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFFAAAAAA),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper to open a conversation from anywhere in the app.
/// Pass [productRef] to automatically send a product reference message.
Future<void> openConversation(
  BuildContext context, {
  required String currentEmail,
  required String currentRole,
  required String sellerEmail,
  required String sellerId,
  required String sellerName,
  String buyerEmail = '',
  String buyerName = '',
  Product? productRef,
}) async {
  final chat = ChatService();

  final isNewRoom = await _isNewRoom(
    buyerEmail: currentRole == 'buyer' ? currentEmail : buyerEmail,
    sellerEmail: currentRole == 'seller' ? currentEmail : sellerEmail,
  );

  final room = await chat.getOrCreateRoom(
    buyerEmail: currentRole == 'buyer' ? currentEmail : buyerEmail,
    sellerEmail: currentRole == 'seller' ? currentEmail : sellerEmail,
    sellerId: sellerId,
    sellerName: sellerName,
    buyerName: currentRole == 'buyer' ? buyerName : buyerName,
  );
  if (room == null || !context.mounted) return;

  // Send product reference if coming from a product page
  if (productRef != null) {
    await chat.sendProductMessage(
      roomId: room.id,
      senderEmail: currentEmail,
      senderRole: currentRole,
      productId: productRef.id.toString(),
      productName: productRef.name,
      productImageUrl: productRef.imageUrl,
      productPrice: productRef.price,
    );
  }

  // Send automated acknowledgement on first contact OR whenever a product is shared
  if (isNewRoom || productRef != null) {
    await chat.sendSystemMessage(
      roomId: room.id,
      content:
          "Hi! Thanks for reaching out to ${sellerName.isNotEmpty ? sellerName : 'the seller'}. "
          "Your message has been sent and they'll reply shortly. "
          "Feel free to share any questions about the product!",
    );
  }

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatConversationScreen(
        room: room,
        currentEmail: currentEmail,
        currentRole: currentRole,
        productJustShared: productRef != null,
      ),
    ),
  );
}

/// Returns true if no room yet exists for this buyer-seller pair.
Future<bool> _isNewRoom({
  required String buyerEmail,
  required String sellerEmail,
}) async {
  try {
    final rows = await Supabase.instance.client
        .from('chat_rooms')
        .select('id')
        .eq('buyer_email', buyerEmail)
        .eq('seller_email', sellerEmail)
        .limit(1);
    return (rows as List).isEmpty;
  } catch (_) {
    return false;
  }
}

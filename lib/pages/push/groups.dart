import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:im_flutter_sdk/im_flutter_sdk.dart';

import '../../models/active.dart';
import '../../utils/logger.dart';
import '../courses/list.dart';
import '../widget/avatar.dart';
import '../../push/easemob.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  List<ChatGroup> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  bool _isCourseGroup(ChatGroup group) {
    final desc = group.desc ?? '';
    if (desc.isEmpty) return false;

    try {
      final data = jsonDecode(desc);
      return data is Map && data.containsKey('courseInfo');
    } catch (_) {
      return false;
    }
  }

  /// 分页拉取当前用户加入的全部群组。
  Future<List<ChatGroup>> _fetchAllJoinedGroups() async {
    final List<ChatGroup> all = [];
    const pageSize = 20;
    var pageNum = 0;

    while (true) {
      final page = await ChatClient.getInstance.groupManager.fetchJoinedGroupsFromServer(
        pageSize: pageSize,
        pageNum: pageNum,
        needMemberCount: true
      );

      all.addAll(page);

      if (page.length < pageSize) break;
      pageNum++;
    }

    return all;
  }

  Future<void> _loadGroups() async {
    if (!EasemobIM().isLoggedIn) {
      if (mounted) {
        setState(() {
          _groups = [];
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final groups = await _fetchAllJoinedGroups();

      // 不显示课程群聊
      final visibleGroups = groups.where((g) => !_isCourseGroup(g)).toList();

      logger.d({'群组列表 JSON': visibleGroups.map((g) => g.toJson()).toList()});

      if (!mounted) return;
      setState(() {
        _groups = visibleGroups;
        _isLoading = false;
      });
    } catch (e) {
      logger.e('加载群聊失败: $e');
      if (!mounted) return;
      setState(() {
        _groups = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('群聊'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadGroups,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _groups.isEmpty
                ? Center(
                    child: Text(
                      EasemobIM().isLoggedIn ? '暂无群聊' : '请到账号列表开启推送服务',
                      style: const TextStyle(fontSize: 18, color: Colors.grey)
                    ),
                  )
                : ListView.builder(
                    itemCount: _groups.length,
                    itemBuilder: (context, index) {
                      final group = _groups[index];
                      final name = group.groupName ?? group.groupId;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: (group.avatarUrl?.isNotEmpty ?? false)
                              ? AvatarWidget(
                                  imageUrl: group.avatarUrl,
                                  size: 50,
                                  borderRadius: 25,
                                  iconSize: 25
                                )
                              : CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                  child: Icon(
                                    Icons.forum,
                                    color: Theme.of(context).colorScheme.onSecondaryContainer
                                  ),
                                ),
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold
                            ),
                          ),
                          subtitle: group.memberCount != null ?
                          Text('${group.memberCount} 名成员') : null,
                          trailing: Icon(
                            Icons.chevron_right,
                            color: Colors.grey[400],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupMessagesPage(group: group)
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

/// 群聊签到消息页面：加载群历史消息，仅保留签到相关消息。
class GroupMessagesPage extends StatefulWidget {
  const GroupMessagesPage({super.key, required this.group});

  final ChatGroup group;

  @override
  State<GroupMessagesPage> createState() => _GroupMessagesPageState();
}

class _GroupMessagesPageState extends State<GroupMessagesPage> {
  List<ChatMessage> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final messages = await _fetchSignInMessages(widget.group.groupId);

      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
    } catch (e) {
      logger.e('加载群历史消息失败: $e');
      if (!mounted) return;
      setState(() {
        _messages = [];
        _isLoading = false;
      });
    }
  }

  /// 结合云端漫游与本地数据库加载群历史消息，仅保留签到相关消息。
  Future<List<ChatMessage>> _fetchSignInMessages(String groupId) async {
    final results = await Future.wait([
      _fetchServerSignInMessages(groupId),
      _fetchLocalSignInMessages(groupId),
    ]);

    final merged = <String, ChatMessage>{};
    for (final list in results) {
      for (final message in list) {
        merged[message.msgId] = message;
      }
    }

    final messages = merged.values.toList()
      ..sort((a, b) => b.serverTime.compareTo(a.serverTime));
    return messages;
  }

  /// 从云端漫游拉取签到消息。
  Future<List<ChatMessage>> _fetchServerSignInMessages(String groupId) async {
    final List<ChatMessage> signInMessages = [];

    try {
      String? cursor;
      var pageCount = 0;
      const maxPages = 20;

      do {
        final result = await ChatClient.getInstance.chatManager.fetchHistoryMessagesByOption(
          groupId,
          ChatConversationType.GroupChat,
          cursor: cursor,
          pageSize: 50,
        );

        for (final message in result.data) {
          logger.d({'云端历史消息 JSON': message.toJson()});
        }

        signInMessages.addAll(result.data.where(_isSignInMessage));
        cursor = result.cursor;
        pageCount++;
      } while (cursor != null && cursor.isNotEmpty && pageCount < maxPages);
    } catch (e) {
      logger.e('加载云端历史消息失败: $e');
    }

    return signInMessages;
  }

  /// 从本地数据库拉取消息。
  Future<List<ChatMessage>> _fetchLocalSignInMessages(String groupId) async {
    final List<ChatMessage> signInMessages = [];

    try {
      final conversation = await ChatClient.getInstance.chatManager.getConversation(
        groupId,
        type: ChatConversationType.GroupChat
      );
      if (conversation == null) return [];

      const pageSize = 50;
      var startMsgId = '';
      var pageCount = 0;
      const maxPages = 20;

      while (pageCount < maxPages) {
        final page = await conversation.loadMessages(
          startMsgId: startMsgId,
          loadCount: pageSize,
          direction: ChatSearchDirection.Up,
        );

        if (page.isEmpty) break;

        for (final message in page) {
          logger.d({'本地历史消息 JSON': message.toJson()});
        }

        signInMessages.addAll(page.where(_isSignInMessage));

        if (page.length < pageSize) break;
        startMsgId = page.last.msgId;
        pageCount++;
      }
    } catch (e) {
      logger.e('加载本地历史消息失败: $e');
    }

    return signInMessages;
  }

  bool _isSignInMessage(ChatMessage message) {
    final activeInfo = _activeInfoOf(message);
    if (activeInfo == null) return false;

    final type = _asInt(activeInfo['atype']);
    return type == ActiveType.signIn.value;
  }

  Map? _activeInfoOf(ChatMessage message) {
    final attributes = message.attributes;
    if (attributes == null) return null;

    final attachment = attributes['attachment'];
    if (attachment is! Map) return null;

    final activeInfo = attachment['att_chat_course'];
    return activeInfo is Map ? activeInfo : null;
  }

  Active _buildActive(ChatMessage message) {
    final activeInfo = _activeInfoOf(message)!;
    return Active(
      type: _asInt(activeInfo['atype']) ?? ActiveType.signIn.value,
      id: activeInfo['aid']?.toString() ?? '',
      name: activeInfo['title']?.toString() ?? '',
      description: activeInfo['subTitle']?.toString() ?? '',
      startTime: 0,
      url: activeInfo['url']?.toString() ?? '',
      attendNum: 0,
      status: true,
    );
  }

  (String, String, String) _courseInfoOf(ChatMessage message) {
    final activeInfo = _activeInfoOf(message)!;
    final courseInfo = activeInfo['courseInfo'];
    if (courseInfo is! Map) return ('', '', '');

    return (
      courseInfo['courseid']?.toString() ?? '',
      courseInfo['classid']?.toString() ?? '',
      courseInfo['coursename']?.toString() ?? '',
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.group.groupName ?? '群聊消息';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMessages,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _messages.isEmpty
                ? const Center(
                    child: Text(
                      '暂无签到消息',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final active = _buildActive(message);
                      final (courseId, classId, courseName) =
                          _courseInfoOf(message);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                            child: Icon(
                              active.getIcon(),
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                          title: Text(
                            active.name.isEmpty ? active.activeType.label : active.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (courseName.isNotEmpty)
                                Text(
                                  courseName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              if (active.description.isNotEmpty)
                                Text(
                                  active.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () async {
                            if (!mounted) return;
                            CoursesPage.navigateToActive(
                              context,
                              active,
                              courseId,
                              classId,
                              ''
                            );
                          }
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

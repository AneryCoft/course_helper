import 'package:flutter/material.dart';

import '../../../api/image.dart';
import '../../../api/sign_in.dart';
import '../../../api/api_service.dart';
import '../../widget/avatar.dart';
import 'sign_in.dart';

class AttendListWidget extends StatefulWidget {
  final SignInPageState state;

  const AttendListWidget({
    super.key,
    required this.state
  });

  @override
  State<AttendListWidget> createState() => _AttendListWidgetState();
}

class _AttendListWidgetState extends State<AttendListWidget> {
  bool _isLoading = false;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadAttendList();
  }

  Future<void> _loadAttendList() async {
    setState(() => _isLoading = true);
    
    try {
      final attendListData = await SignInApi.getGroupAttendList(widget.state.widget.active.id);
      if (attendListData != null && mounted) {
        widget.state.signParams.groupSignedList = List<Map<String, dynamic>>.from(attendListData['yiqianList'] ?? []);
        widget.state.refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshList() async {
    await _loadAttendList();
  }

  void _handleItemClick(String title, double longitude, double latitude) {
    // 拍照签到：分配照片ID
    if (widget.state.needPhoto) {
      final selectedAccounts = widget.state.selectedAccounts;
      if (selectedAccounts.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('请先选择签到账号'), backgroundColor: Colors.red),
        );
        return;
      }

      // 找到第一个没有objectId的账号
      for (var user in selectedAccounts) {
        final existingObjectId = widget.state.signParams.getUserObjectId(user.uid);
        if (existingObjectId == null) {
          widget.state.signParams.setUserObjectId(user.uid, title.toString());
          widget.state.setObjectIdForUser(user.uid, title.toString());
          widget.state.refresh();
          return;
        }
      }
    } else if (longitude != 0.0 && latitude != 0.0) { // 位置签到：填充位置参数
      widget.state.signParams.address = title;
      widget.state.signParams.longitude = longitude;
      widget.state.signParams.latitude = latitude;
      widget.state.refresh();
    }
  }

  Widget _buildSignedItem(Map<String, dynamic> signData) {
    final String name = signData['name'];
    final String uid = signData['uid'];
    final int updateTime = signData['updatetime'];
    final String? title = signData['title'];

    final double longitude = signData['longitude'];
    final double latitude = signData['latitude'];

    final dateTime = DateTime.fromMillisecondsSinceEpoch(updateTime);
    final timeFormatted = '${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

    Widget? extraWidget;
    if (title != null && title.isNotEmpty) {
      if (widget.state.needPhoto) {
        extraWidget = GestureDetector(
          onTap: () => _showImageDialog(context, title),
          child: Image.network(
            CXImageApi.getImageUrlWithSize(title, 50, 60),
            headers: HeadersManager.chaoxingHeaders,
            width: 50,
            height: 60,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const SizedBox(
                width: 50,
                height: 60,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2))
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              width: 50,
              height: 60,
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, size: 24)
            )
          ),
        );
      }
      else {
        // 地址
        extraWidget = Flexible(
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        );
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: InkWell(
        onTap: () => {
          if (title != null) _handleItemClick(title, longitude, latitude)
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
          children: [
            AvatarWidget(
              imageUrl: CXImageApi.getAvatarUrlByUid(uid, 80),
              size: 40,
              borderRadius: 20,
              iconSize: 20
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    timeFormatted,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  )
                ],
              ),
            ),
            if (extraWidget != null) ...[
              const SizedBox(width: 8),
              extraWidget,
            ],
          ],
        ),
      ),
      ),
    );
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black12,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                CXImageApi.getImageUrlWithSize(imageUrl, null, null),
                headers: HeadersManager.chaoxingHeaders,
                fit: BoxFit.contain
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signedList = widget.state.signParams.groupSignedList ?? [];
    
    if (signedList.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '签到列表',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold
                )
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _refreshList,
                tooltip: '刷新'
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _isExpanded = expanded;
            });
          },
          title: Text(
            '已签到 (${signedList.length}人)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _refreshList,
                tooltip: '刷新'
              ),
              Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.grey
              ),
            ],
          ),
          children: [
            ...signedList.map((item) => _buildSignedItem(item)),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator())
              ),
          ],
        ),
      ),
    );
  }
}

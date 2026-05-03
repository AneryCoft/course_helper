import 'package:flutter/material.dart';

import '../../api/course.dart';
import '../../models/active.dart';
import 'list.dart';
import 'settings.dart';


class CourseContentPage extends StatefulWidget {
  final String courseId;
  final String courseName;
  final String classId;
  final String cpi;

  const CourseContentPage({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.classId,
    required this.cpi,
  });

  @override
  State<CourseContentPage> createState() => _CourseContentPageState();
}

class _CourseContentPageState extends State<CourseContentPage> {
  List<Active> _activeList = [];
  bool _isContentLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCourseContent();
  }

  Future<void> _loadCourseContent() async {
    setState(() {
      _isContentLoading = true;
    });

    try {
      final List<Active>? contentList = await CXCourseApi.getActiveList(
        widget.courseId,
        widget.classId,
        widget.cpi,
      );

      if (contentList != null) {
        setState(() {
          _activeList = contentList;
          _isContentLoading = false;
        });
      } else {
        setState(() {
          _activeList = [];
          _isContentLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取内容列表失败')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _activeList = [];
        _isContentLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取内容列表时发生错误：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseName),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CourseSettingsPage(
                    courseId: widget.courseId
                  ),
                ),
              );
            },
            tooltip: '课程设置'
          ),
        ],
      ),
      body: _isContentLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeList.isEmpty
          ? const Center(
        child: Text(
          '暂无内容',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadCourseContent,
        child: ListView.builder(
          itemCount: _activeList.length,
          itemBuilder: (context, index) {
            var active = _activeList[index];
            return Card(
              margin: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    active.getIcon(),
                    color: active.status
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    size: 35,
                  ),
                ),
                title: Text(
                  active.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active.description.isEmpty ?
                      '手动结束' : active.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '参与人数：${active.attendNum}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey
                      )
                    )
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  CoursesPage.navigateToActive(context, active, widget.courseId, widget.classId, widget.cpi);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

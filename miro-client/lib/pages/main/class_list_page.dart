import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

// 페이지 import
import '../chat/chat_page.dart';
import '../myclass/myclass_page.dart';
import '../mypage/mypage_page.dart';
import '../createClass/create_class_page.dart';

class ClassListPage extends StatefulWidget {
  const ClassListPage({super.key});

  @override
  State<ClassListPage> createState() => _ClassListPageState();
}

class _ClassListPageState extends State<ClassListPage> {
  int _selectedIndex = 0;
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  List<Map<String, dynamic>> _openClasses = [];
  bool _isLoadingClasses = true;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchOpenClasses();
  }

  //  동적 데이터를 안전하게 문자열로 변환 (Map 형태 및 String 형태 모두 처리)
  String _getStringFromDynamic(dynamic data, String defaultValue) {
    if (data == null) {
      return defaultValue;
    }
    if (data is String) {
      return data;
    }
    if (data is Map<String, dynamic>) {
      // Map 형태라면, 'value' 키의 값을 문자열로 반환 시도
      return data['value'] is String
          ? data['value']
          : data.values.whereType<String>().isNotEmpty
          ? data.values.whereType<String>().first
          : defaultValue;
    }
    // 그 외의 기본 타입 (int, bool 등)은 toString()으로 변환
    return data.toString();
  }

  // 멘토 정보 (이름, 학년/반) 조회
  Future<Map<String, String>> _fetchMentorDetails(String creatorUid) async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(creatorUid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final String nickname = userData['nickname'] ?? '멘토 이름 없음';

        final String grade = userData['grade'] != null
            ? '${userData['grade']}'
            : '';
        final String classroom = userData['class_room'] != null
            ? '${userData['class_room']}'
            : '';
        final String number = userData['number'] != null
            ? '${userData['number']}번'
            : '';

        String mentorGrade = '';
        if (grade.isNotEmpty || classroom.isNotEmpty || number.isNotEmpty) {
          mentorGrade = '$grade $classroom $number'.trim();
        } else {
          mentorGrade = '정보 없음';
        }

        return {'mentorName': nickname, 'mentorGrade': mentorGrade};
      }
      return {'mentorName': '사용자 없음', 'mentorGrade': '정보 없음'};
    } catch (e) {
      print("멘토 정보 조회 오류 ($creatorUid): $e");
      return {'mentorName': '오류 발생', 'mentorGrade': '정보 없음'};
    }
  }

  Future<void> _fetchOpenClasses() async {
    setState(() => _isLoadingClasses = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final response = await http.get(
        Uri.parse('http://localhost:3000/classList/open'),
        headers: {'x-uid': user.uid},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _openClasses = List<Map<String, dynamic>>.from(data['data']);
          _isLoadingClasses = false;
        });
      } else {
        print("API 호출 실패: ${response.statusCode}");
        setState(() => _isLoadingClasses = false);
      }
    } catch (e) {
      print("API 호출 에러: $e");
      setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _joinClass(String classUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final response = await http.post(
        Uri.parse('http://localhost:3000/classList/join'),
        headers: {'x-uid': user.uid, 'Content-Type': 'application/json'},
        body: jsonEncode({'classUid': classUid}),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '참가 완료! 현재 인원: ${data['data']['currentParticipants']}',
            ),
          ),
        );
        _fetchOpenClasses();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('참가 실패: ${data['message'] ?? response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      print('참가 API 호출 에러: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('참가 중 오류 발생')));
    }
  }

  // --- 클래스 상세 정보 모달 표시 메서드 ---
  void _showClassDetailModal(Map<String, dynamic> classData) {
    final String classId = classData['classUid'] ?? 'unknown_id';
    final String className = classData['className'] ?? '제목 없음';
    final String description = classData['description'] ?? '설명 없음';
    final String field = classData['field'] ?? '';
    final int capacity = classData['capacity'] ?? 0;
    final String creatorUid = classData['creatorUid'] ?? '';

    // Map 또는 null 값 오류를 방지하기 위해 헬퍼 함수 사용
    final String requirement = _getStringFromDynamic(
      classData['requirement'],
      '없음',
    );
    final String caution = _getStringFromDynamic(classData['caution'], '없음');

    // 날짜 변환 헬퍼 함수
    DateTime? _dateTimeFromMap(Map<String, dynamic>? map) {
      if (map == null) return null;
      if (map.containsKey('_seconds')) {
        return DateTime.fromMillisecondsSinceEpoch(map['_seconds'] * 1000);
      }
      return null;
    }

    // 날짜 데이터 가져오기
    String period = '기간 정보 없음';
    try {
      final startDate = _dateTimeFromMap(
        classData['startDate'] as Map<String, dynamic>?,
      );
      final endDate = _dateTimeFromMap(
        classData['endDate'] as Map<String, dynamic>?,
      );

      if (startDate != null && endDate != null) {
        period =
            '${DateFormat('yyyy. MM. dd').format(startDate)} ~ ${DateFormat('yyyy. MM. dd').format(endDate)}';
      }
    } catch (e) {
      print("날짜 변환 오류: $e");
      period = '기간 정보 오류';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30.0),
              topRight: Radius.circular(30.0),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: FutureBuilder<Map<String, String>>(
                future: _fetchMentorDetails(creatorUid),
                builder: (context, snapshot) {
                  String mentorName = '로딩 중...';
                  String mentorGrade = '정보 로딩 중...';

                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    mentorName = snapshot.data!['mentorName']!;
                    mentorGrade = snapshot.data!['mentorGrade']!;
                  } else if (snapshot.hasError) {
                    mentorName = '조회 오류';
                    mentorGrade = '오류';
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          height: 5,
                          width: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 16.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              className,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF212121),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              description,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF757575),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mentorName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      mentorGrade,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9E9E9E),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Divider(),
                            _buildInfoRow("분야", field),
                            _buildInfoRow("인원", "${capacity}인"),
                            _buildInfoRow("기간", period),
                            _buildInfoRow("조건", requirement),
                            _buildInfoRow("주의", caution, isNotice: true),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (snapshot.connectionState ==
                                  ConnectionState.done &&
                              snapshot.hasData) {
                            _joinClass(classId);
                          }
                        },
                        child: Container(
                          height: 56,
                          width: double.infinity,
                          margin: const EdgeInsets.only(
                            left: 24,
                            right: 24,
                            bottom: 30,
                            top: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6DEDC2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            snapshot.connectionState != ConnectionState.done
                                ? '정보 로딩 중...'
                                : '참여하기',
                            style: const TextStyle(
                              color: Color(0xFF424242),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // 모달 내 정보 표시 Row 위젯 (변경 없음)
  Widget _buildInfoRow(String title, String content, {bool isNotice = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(
              title,
              style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              content,
              style: TextStyle(
                color: isNotice
                    ? const Color.fromARGB(255, 227, 67, 67)
                    : const Color(0xFF212121),
                fontSize: 14,
                fontWeight: isNotice ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
  // ------------------------------------

  void _onNavTap(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildTabPage(int index) {
    switch (index) {
      case 0:
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // 헤더
                    Container(
                      height: 207,
                      width: double.infinity,
                      color: const Color(0xFFF5F5F5),
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 32,
                      ),
                      child: const Text(
                        "오늘은 어떤 성장을\n이뤄볼까요?",
                        style: TextStyle(
                          color: Color(0xFF212121),
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // 클래스 리스트
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: _isLoadingClasses
                            ? const Center(child: CircularProgressIndicator())
                            : _openClasses.isEmpty
                            ? const Center(
                                child: Text(
                                  "열린 클래스가 없습니다",
                                  style: TextStyle(fontSize: 16),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _openClasses.map((classData) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: GestureDetector(
                                      onTap: () {
                                        _showClassDetailModal(classData);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // 커버 이미지
                                            if (classData['coverImg'] != null &&
                                                classData['coverImg']
                                                    .isNotEmpty)
                                              Expanded(
                                                flex: 0,
                                                child: Image.asset(
                                                  "assets/coverImg/cover.png",
                                                  width: 80,
                                                  height: 80,
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            else
                                              Container(
                                                width: 80,
                                                height: 80,
                                                color: Colors.grey,
                                                child: const Icon(
                                                  Icons.image,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    classData['className'] ??
                                                        '',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    classData['description'] ??
                                                        '',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    "분야: ${classData['field'] ?? ''} / 인원: ${classData['capacity'] ?? ''}",
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 1:
        return MyClassPage();
      case 2:
        return ChatPage();
      case 3:
        return MyPage();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final navs = List<Widget>.generate(4, (i) {
      return Offstage(
        offstage: _selectedIndex != i,
        child: Navigator(
          key: _navigatorKeys[i],
          onGenerateRoute: (_) =>
              MaterialPageRoute(builder: (_) => _buildTabPage(i)),
        ),
      );
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          ...navs,
          // 플로팅 네비게이션 바
          Positioned(
            bottom: 53,
            left: MediaQuery.of(context).size.width / 2 - 361 / 2,
            child: Container(
              width: 361,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFCECECE), width: 1),
              ),
              child: Row(
                children: [
                  _NavBarItem(
                    iconPath: "assets/icons/home_icon.png",
                    hoverIconPath: "assets/icons/home_hover_icon.png",
                    label: "홈",
                    isSelected: _selectedIndex == 0,
                    onTap: () => _onNavTap(0),
                  ),
                  _NavBarItem(
                    iconPath: "assets/icons/class_icon.png",
                    hoverIconPath: "assets/icons/class_hover_icon.png",
                    label: "내 수업",
                    isSelected: _selectedIndex == 1,
                    onTap: () => _onNavTap(1),
                  ),
                  _NavBarItem(
                    iconPath: "assets/icons/chat_icon.png",
                    hoverIconPath: "assets/icons/chat_hover_icon.png",
                    label: "채팅",
                    isSelected: _selectedIndex == 2,
                    onTap: () => _onNavTap(2),
                  ),
                  _NavBarItem(
                    iconPath: "assets/icons/mypage_icon.png",
                    hoverIconPath: "assets/icons/mypage_hover_icon.png",
                    label: "마이페이지",
                    isSelected: _selectedIndex == 3,
                    onTap: () => _onNavTap(3),
                  ),
                ],
              ),
            ),
          ),
          // 원형 버튼 (+)
          Positioned(
            bottom: 150,
            right: 16,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateClassPage(),
                  ),
                );
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFF6DEDC2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  color: Color(0xFF424242),
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final String iconPath;
  final String hoverIconPath;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.iconPath,
    required this.hoverIconPath,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              isSelected ? hoverIconPath : iconPath,
              width: 24,
              height: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? const Color(0xFF52B292)
                    : const Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

// Local storage imports (no Firebase required!)
import 'package:senyamatika_math_app/backend/services/local_storage_service.dart';
import 'package:senyamatika_math_app/backend/services/local_auth_service.dart';
import 'package:senyamatika_math_app/backend/services/database_seeder.dart';
import 'package:senyamatika_math_app/backend/services/sign_language_service.dart';
import 'package:senyamatika_math_app/backend/services/user_provider.dart' as backend;
import 'package:senyamatika_math_app/backend/services/api_service.dart';
import 'package:senyamatika_math_app/backend/services/dev_student_bootstrap.dart';
import 'package:senyamatika_math_app/backend/services/data_sync_service.dart';

// Exercise feature module
import 'package:senyamatika_math_app/features/exercise/screens/exercise_screen.dart'
    as exercise_feature;
import 'package:senyamatika_math_app/features/exercise/data/whole_numbers_questions.dart';
import 'package:senyamatika_math_app/features/exercise/data/comparison_questions.dart';
import 'package:senyamatika_math_app/features/exercise/data/fundamental_operations_questions.dart';
import 'package:senyamatika_math_app/features/exercise/data/fractions_questions.dart';
import 'package:senyamatika_math_app/features/exercise/data/decimals_questions.dart';
import 'package:senyamatika_math_app/features/exercise/data/percentages_questions.dart';
import 'package:senyamatika_math_app/features/exercise/data/algebra_questions.dart';
import 'package:senyamatika_math_app/features/exercise/ai/exercise_ai_policy.dart';

// ============ LEGACY USER DATA (Kept for backward compatibility) ============
class UserData {
  String name;
  String email;
  String? school;
  String? section;
  
  UserData({
    required this.name,
    required this.email,
    this.school,
    this.section,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'school': school,
      'section': section,
    };
  }
  
  factory UserData.fromMap(Map<String, dynamic> map) {
    return UserData(
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      school: map['school'],
      section: map['section'],
    );
  }
}

// Legacy UserProvider - kept for backward compatibility
class UserProvider {
  static UserData? _currentUser;
  static Map<String, Map<String, dynamic>> _userCredentials = {};
  
  static void setUser(UserData user) {
    _currentUser = user;
  }
  
  static void saveCredentials(String email, Map<String, dynamic> credentials) {
    _userCredentials[email] = credentials;
  }
  
  static Map<String, dynamic>? getCredentials(String email) {
    return _userCredentials[email];
  }
  
  static bool validateLogin(String email, String password) {
    final credentials = _userCredentials[email];
    if (_userCredentials.isEmpty) return true;
    return credentials != null && credentials['password'] == password;
  }
  
  static UserData? getCurrentUser() {
    return _currentUser;
  }
  
  static String getUserName() {
    return _currentUser?.name.isNotEmpty == true ? _currentUser!.name : 'User';
  }
  
  static String getUserEmail() {
    return _currentUser?.email ?? '';
  }
  
  static String? getUserSchool() {
    return _currentUser?.school;
  }
  
  static String? getUserSection() {
    return _currentUser?.section;
  }
  
  static void updateUserInfo({
    String? name,
    String? email,
    String? school,
    String? section,
  }) {
    if (_currentUser != null) {
      _currentUser = UserData(
        name: name ?? _currentUser!.name,
        email: email ?? _currentUser!.email,
        school: school ?? _currentUser!.school,
        section: section ?? _currentUser!.section,
      );
      
      if (email != null && email != _currentUser!.email) {
        final oldCredentials = _userCredentials[_currentUser!.email];
        if (oldCredentials != null) {
          _userCredentials[email] = oldCredentials;
          _userCredentials.remove(_currentUser!.email);
        }
      }
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Local Storage (Hive)
  try {
    await LocalStorageService.initialize();
    print('✅ Local database initialized successfully');
    
    // Seed database with default users
    final seeder = DatabaseSeeder();
    await seeder.seedDatabase();
    
    // Sign language dataset is now rule-based (numbers 0-9 available)
    print('✅ Sign language service ready: ${SignLanguageService.getDatasetSize()} signs available');
  } catch (e) {
    print('⚠️ Local database initialization failed: $e');
  }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => backend.UserProvider()),
      ],
      child: const SenyaMatikaApp(),
    ),
  );
}

class SenyaMatikaApp extends StatelessWidget {
  const SenyaMatikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SenyaMatika',
      theme: ThemeData(
        primaryColor: Colors.yellow[600],
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateAfterSplash();
  }

  Future<void> _navigateAfterSplash() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    final devUser = await DevStudentBootstrap.ensureDebugStudent();
    if (devUser != null) {
      UserProvider.setUser(UserData(
        name: devUser.name,
        email: devUser.email,
        school: devUser.school,
        section: devUser.section,
      ));
      progressManager.setCurrentUser(devUser.uid);
      ApiService.setStudentId(devUser.uid);
      if (!mounted) return;
      try {
        await Provider.of<backend.UserProvider>(context, listen: false)
            .loadUserData(devUser.uid);
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const FrontPageScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image(
              image: const AssetImage('assets/images/applogo.png'),
              height: 300,
            ),
            const SizedBox(height: 20),
            const Text(
              'SenyaMatika',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                fontFamily: 'Lora-Regular',
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// Responsive Helper Class
class ResponsiveHelper {
  static double getResponsiveValue(
    BuildContext context, {
    required double mobile,
    required double tablet,
    required double desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width < 600) {
      return mobile;
    } else if (width < 1200) {
      return tablet;
    } else {
      return desktop;
    }
  }

  static bool isMobile(BuildContext context) => 
      MediaQuery.of(context).size.width < 600;
  
  static bool isTablet(BuildContext context) => 
      MediaQuery.of(context).size.width >= 600 && 
      MediaQuery.of(context).size.width < 1200;
  
  static bool isDesktop(BuildContext context) => 
      MediaQuery.of(context).size.width >= 1200;
  
  static double screenWidth(BuildContext context) => 
      MediaQuery.of(context).size.width;
  
  static double screenHeight(BuildContext context) => 
      MediaQuery.of(context).size.height;
}

// ============ DASHBOARD SCREEN ============
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> 
    with TickerProviderStateMixin {
  late AnimationController _featureAnimationController;
  late PageController _storyPageController;
  int _currentStoryIndex = 0;
  bool _isProfileDrawerOpen = false;

  // COLORS FROM THE AVATAR
  final Color lightPink = const Color(0xFFFADADD);      // Light pink ng skin/cheeks
  final Color mintGreen = const Color(0xFFC7F0DB);      // Mint green ng shirt/background
  final Color softBlue = const Color(0xFFB7E0FF);       // Soft blue ng eyes/details
  final Color peach = const Color(0xFFFFE5B4);          // Peach ng hair/face
  final Color lavender = const Color(0xFFE0D7FF);       // Light lavender

  // DARKER VERSIONS OF THE COLORS FOR BORDERS
  Color getDarkerColor(Color color) {
    if (color == mintGreen) return const Color(0xFF6BAF8C); // Darker mint green
    if (color == lightPink) return const Color(0xFFE6A8A8); // Darker pink
    if (color == softBlue) return const Color(0xFF7FA9C9);  // Darker blue
    if (color == lavender) return const Color(0xFFB19CD9);  // Darker lavender
    return color.withOpacity(0.8); // Fallback
  }

  List<Map<String, dynamic>> _getStories(BuildContext context) {
    return [
      {
        'title': 'Welcome to SenyaMatika!',
        'subtitle': 'Interactive Math Learning',
        'color': mintGreen,
        'icon': Icons.school,
        'description': 'Discover a new way to learn mathematics',
        'image': 'assets/images/myimage.png',
        'onTap': () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Welcome to SenyaMatika!'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        'type': 'app_intro'
      },
      {
        'title': 'Meet Our Avatar',
        'subtitle': 'Sign Language Instructor',
        'color': lightPink,
        'icon': Icons.face,
        'description': 'Learn mathematics through sign language',
        'image': 'assets/Videos/Avatar.mp4',
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SignLanguageAvatarScreen()),
          );
        },
        'type': 'avatar'
      },
      {
        'title': 'Explore Our Topics',
        'subtitle': 'Learn Different Math Concepts',
        'color': peach,
        'icon': Icons.menu_book,
        'description': 'Click to explore all math topics',
        'image': 'assets/images/topics.png',
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TopicsScreen()),
          );
        },
        'type': 'topics'
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _featureAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    _storyPageController = PageController(viewportFraction: 0.88);
    _startAutoRotation();
  }
  
  void _startAutoRotation() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        if (_currentStoryIndex < _getStories(context).length - 1) {
          _storyPageController.nextPage(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          _storyPageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
        _startAutoRotation();
      }
    });
  }

  @override
  void dispose() {
    _featureAnimationController.dispose();
    _storyPageController.dispose();
    super.dispose();
  }

  void _toggleProfileDrawer() {
    setState(() {
      _isProfileDrawerOpen = !_isProfileDrawerOpen;
    });
  }

  Widget _buildAnimatedFeatureIcon({
    required String assetPath,
    required Color fallbackColor,
    required IconData fallbackIcon,
    required BuildContext context,
  }) {
    final size = ResponsiveHelper.screenWidth(context) < 600 ? 60.0 : 70.0;
    
    return AnimatedBuilder(
      animation: _featureAnimationController,
      builder: (context, child) {
        final bounceValue = (sin(_featureAnimationController.value * 2 * 3.14) * 8);
        return Transform.translate(
          offset: Offset(0, bounceValue),
          child: child,
        );
      },
      child: Image.asset(
        assetPath,
        height: size,
        width: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: size,
            width: size,
            decoration: BoxDecoration(
              color: fallbackColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                fallbackIcon,
                size: size * 0.5,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildStoryCard(Map<String, dynamic> story, int index, BuildContext context) {
    return GestureDetector(
      onTap: () {
        story['onTap']();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: story['color'],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: story['image'] != null
                        ? ClipOval(
                            child: Image.asset(
                              story['image'],
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  story['icon'],
                                  color: Colors.black,
                                  size: 30,
                                );
                              },
                            ),
                          )
                        : Icon(
                            story['icon'],
                            color: Colors.black,
                            size: 30,
                          ),
                  ),
                  
                  if (index == 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.white,
                              blurRadius: 2,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              
              const Spacer(),
              
              Text(
                story['title'],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 6),
              
              Text(
                story['subtitle'],
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 8),
              
              Text(
                story['description'],
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black.withOpacity(0.6),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stories = _getStories(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Senyamatika',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            
                            GestureDetector(
                              onTap: _toggleProfileDrawer,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Image.asset(
                                    'assets/images/menu.png',
                                    width: 40,
                                    height: 35,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.menu,
                                        color: Colors.black,
                                        size: 30,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 28),
                        
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'Discover',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(color: mintGreen, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 5,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${_currentStoryIndex + 1}/${stories.length}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // TATLONG CONTAINER NA GUMA GALAW
                            SizedBox(
                              height: isSmallScreen ? 200 : 220,
                              child: PageView.builder(
                                controller: _storyPageController,
                                onPageChanged: (index) {
                                  setState(() {
                                    _currentStoryIndex = index;
                                  });
                                },
                                itemCount: stories.length,
                                itemBuilder: (context, index) {
                                  return _buildStoryCard(stories[index], index, context);
                                },
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // ============ NAKASENTRO NA ANG TATLONG DOTS ============
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(stories.length, (index) {
                                    return Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _currentStoryIndex == index 
                                            ? mintGreen
                                            : Colors.grey[300],
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 32),
                        
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Features',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  // APAT NA FEATURES BOXES - MAY DARKER BORDERS NA
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 20 : screenWidth * 0.05,
                    ),
                    child: Column(
                      children: [
                        // First Row - 2 boxes (Topics & Progress)
                        Row(
                          children: [
                            // Topics Box (Mint Green with Darker Border)
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const TopicsScreen()),
                                  );
                                },
                                child: Container(
                                  height: isSmallScreen ? 160 : 180,
                                  margin: const EdgeInsets.only(right: 12),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: mintGreen,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: getDarkerColor(mintGreen), // Darker mint green border
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 15,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildAnimatedFeatureIcon(
                                        assetPath: 'assets/images/topics.png',
                                        fallbackColor: mintGreen,
                                        fallbackIcon: Icons.menu_book,
                                        context: context,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Topics',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          shadows: [
                                            Shadow(
                                              color: Colors.white,
                                              blurRadius: 3,
                                              offset: Offset(1, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Progress Box (Light Pink with Darker Border)
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const StudentProgressScreen()),
                                  );
                                },
                                child: Container(
                                  height: isSmallScreen ? 160 : 180,
                                  margin: const EdgeInsets.only(left: 12),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: lightPink,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: getDarkerColor(lightPink), // Darker pink border
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 15,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildAnimatedFeatureIcon(
                                        assetPath: 'assets/images/to-do-list.png',
                                        fallbackColor: lightPink,
                                        fallbackIcon: Icons.trending_up,
                                        context: context,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Progress',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          shadows: [
                                            Shadow(
                                              color: Colors.white,
                                              blurRadius: 3,
                                              offset: Offset(1, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Second Row - 2 boxes (Sign Dictionary & Sign Language Avatar)
                        Row(
                          children: [
                            // Sign Dictionary Box (Soft Blue with Darker Border)
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const SignDictionaryScreen()),
                                  );
                                },
                                child: Container(
                                  height: isSmallScreen ? 160 : 180,
                                  margin: const EdgeInsets.only(right: 12),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: softBlue,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: getDarkerColor(softBlue), // Darker blue border
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 15,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildAnimatedFeatureIcon(
                                        assetPath: 'assets/images/dictionary.png',
                                        fallbackColor: softBlue,
                                        fallbackIcon: Icons.library_books,
                                        context: context,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Sign Dictionary',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          shadows: [
                                            Shadow(
                                              color: Colors.white,
                                              blurRadius: 3,
                                              offset: Offset(1, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Sign Language Avatar Box (Lavender with Darker Border)
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const SignLanguageAvatarScreen()),
                                  );
                                },
                                child: Container(
                                  height: isSmallScreen ? 160 : 180,
                                  margin: const EdgeInsets.only(left: 12),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: lavender,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: getDarkerColor(lavender), // Darker lavender border
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 15,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildAnimatedFeatureIcon(
                                        assetPath: 'assets/images/sign-language.png',
                                        fallbackColor: lavender,
                                        fallbackIcon: Icons.face,
                                        context: context,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Sign Avatar',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          shadows: [
                                            Shadow(
                                              color: Colors.white,
                                              blurRadius: 3,
                                              offset: Offset(1, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          if (_isProfileDrawerOpen)
            GestureDetector(
              onTap: _toggleProfileDrawer,
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            right: _isProfileDrawerOpen ? 0 : -MediaQuery.of(context).size.width,
            top: 0,
            bottom: 0,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.75,
              constraints: const BoxConstraints(maxWidth: 300),
              color: Colors.white,
              child: _buildProfileDrawerContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDrawerContent(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 120,
          width: double.infinity,
          color: mintGreen,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Account Menu',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'Manage your account settings',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Profile Option
              _buildDrawerMenuItem(
                title: 'Profile',
                icon: Icons.person,
                onTap: () {
                  _toggleProfileDrawer();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen()),
                  );
                },
                context: context,
              ),
              const SizedBox(height: 12),
              
              _buildDrawerMenuItem(
                title: 'Terms and Policies',
                icon: Icons.settings,
                onTap: () {
                  _toggleProfileDrawer();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                },
                context: context,
              ),
              const SizedBox(height: 12),
              _buildDrawerMenuItem(
                title: 'Help',
                icon: Icons.help_outline,
                onTap: () {
                  _toggleProfileDrawer();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HelpScreen()),
                  );
                },
                context: context,
              ),
              const SizedBox(height: 12),
              _buildDrawerMenuItem(
                title: 'About',
                icon: Icons.info_outline,
                onTap: () {
                  _toggleProfileDrawer();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AboutScreen()),
                  );
                },
                context: context,
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Divider(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              
              _buildLogOutButton(context),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.close, 
                size: 30, 
                color: Colors.black,
              ),
              onPressed: _toggleProfileDrawer,
            ),
          ),
        ),
      ],
    );
  }

  // Helper method para sa iba't ibang border colors ng drawer items
  Color _getBorderColor(String title) {
    switch (title) {
      case 'Profile':
        return mintGreen;      // Mint green
      case 'Terms and Policies':
      case 'Settings':
        return lightPink;      // Light pink (same as Progress box)
      case 'Help':
        return softBlue;       // Soft blue
      case 'About':
        return lavender;       // Lavender
      default:
        return Colors.grey.shade300;
    }
  }

  Widget _buildDrawerMenuItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _getBorderColor(title),  // <- IBA'T IBANG KULAY NG BORDER
              width: 2.5,  // Mas makapal para kita
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                spreadRadius: 0.5,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.black,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogOutButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _toggleProfileDrawer();
          
          // Clear user data on sign out
          UserProvider.setUser(UserData(name: '', email: ''));
          
          // Clear progress manager user (saves progress before clearing)
          progressManager.setCurrentUser(null);
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign out successfully'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );

          Future.delayed(const Duration(milliseconds: 1500), () {
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const FrontPageScreen()),
              (route) => false,
            );
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.25),
                blurRadius: 10,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.logout,
                  color: Colors.red.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ============ EXERCISE SCREEN ============
// SIGN DICTIONARY SCREEN - UPDATED WITH ONLY REMAINING CATEGORIES
class SignDictionaryScreen extends StatelessWidget {
  const SignDictionaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Sign Dictionary',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'Lora-Regular',
              ),
            ),
            Text(
              'Category',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'Lora-Regular',
              ),
            ),
            const SizedBox(height: 30),
            
            Column(
              children: [
                // Numbers & Operators Category (using actual dataset)
                _buildCategoryItem(
                  'Numbers & Operators',
                  const Color(0xFFFEDA5F),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NumbersOperatorsDictionaryScreen()),
                    );
                  },
                ),
                const SizedBox(height: 15),
                
                Row(
                  children: [
                    Expanded(
                      child: _buildCategoryItem(
                        'Fraction',
                        const Color(0xFFA8D5E3),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const FractionDictionaryScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: _buildCategoryItem(
                        'Algebra',
                        const Color(0xFF9C89B8),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AlgebraDictionaryScreen()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                
                Row(
                  children: [
                    Expanded(
                      child: _buildCategoryItem(
                        'Arithmetic Operations',
                        const Color(0xFF90BE6D),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ArithmeticOperationsDictionaryScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: _buildCategoryItem(
                        'Convert',
                        const Color(0xFF277DA1),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ConvertDictionaryScreen()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                
                Row(
                  children: [
                    Expanded(
                      child: _buildCategoryItem(
                        'Learner',
                        const Color.fromARGB(255, 246, 102, 104),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LearnerDictionaryScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: _buildCategoryItem(
                        'Coming Soon',
                        const Color(0xFFCCCCCC),
                        onTap: null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(String title, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 1),
        ),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Lora-Regular',
            ),
          ),
        ),
      ),
    );
  }
}

class ArithmeticOperationsDictionaryScreen extends StatelessWidget {
  const ArithmeticOperationsDictionaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> operationTerms = {
      'Fundamental Operation': 'assets/DataSet/Dictionary/sign-fundamental-operation.webm',
      'Increase': 'assets/DataSet/Dictionary/sign-increase.webm',
      'Decrease': 'assets/DataSet/Dictionary/sign-decrease.webm',
      'Greatest': 'assets/DataSet/Dictionary/sign-greatest.webm',
      'Least': 'assets/DataSet/Dictionary/sign-least.webm',
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Arithmetic Operations',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 0.85,
        ),
        itemCount: operationTerms.length,
        itemBuilder: (context, index) {
          final entry = operationTerms.entries.elementAt(index);
          return _buildTermCard(context, entry.key, entry.value, const Color(0xFF90BE6D));
        },
      ),
    );
  }
}

class ConvertDictionaryScreen extends StatelessWidget {
  const ConvertDictionaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> convertTerms = {
      'Convert': 'assets/DataSet/Dictionary/sign-convert.webm',
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Convert',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 0.85,
        ),
        itemCount: convertTerms.length,
        itemBuilder: (context, index) {
          final entry = convertTerms.entries.elementAt(index);
          return _buildTermCard(context, entry.key, entry.value, const Color(0xFF277DA1));
        },
      ),
    );
  }
}



class LearnerDictionaryScreen extends StatelessWidget {
  const LearnerDictionaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> learnerTerms = {
      'Math': 'assets/DataSet/Dictionary/sign-math.webm',
      'Number': 'assets/DataSet/Dictionary/sign-number.webm',
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Learner',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 0.85,
        ),
        itemCount: learnerTerms.length,
        itemBuilder: (context, index) {
          final entry = learnerTerms.entries.elementAt(index);
          return _buildTermCard(context, entry.key, entry.value, const Color.fromARGB(255, 246, 102, 104));
        },
      ),
    );
  }
}


// ENHANCED VIDEO PLAYER SCREEN WITH SPEED CONTROL
class DictionaryVideoScreen extends StatefulWidget {
  final String title;
  final String videoAsset;
  final Color backgroundColor;

  const DictionaryVideoScreen({
    super.key,
    required this.title,
    required this.videoAsset,
    required this.backgroundColor,
  });

  @override
  State<DictionaryVideoScreen> createState() => _DictionaryVideoScreenState();
}

class _DictionaryVideoScreenState extends State<DictionaryVideoScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset(widget.videoAsset);
      
      await _videoController.initialize();
      
      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
      });
      
      _videoController.setLooping(true);
      _videoController.play();
      
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _changePlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _videoController.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _hasError
                  ? _buildErrorWidget()
                  : _isVideoInitialized
                      ? _buildVideoPlayer()
                      : _buildLoadingWidget(),
            ),
          ),
          if (_isVideoInitialized && !_hasError)
            _buildVideoControls(),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return AspectRatio(
      aspectRatio: _videoController.value.aspectRatio,
      child: VideoPlayer(_videoController),
    );
  }

  Widget _buildLoadingWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: Colors.black),
        const SizedBox(height: 20),
        Text(
          'Loading video...',
          style: TextStyle(
            fontSize: 16,
            fontFamily: 'Poppins-Regular',
          ),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 60, color: Colors.red),
        const SizedBox(height: 20),
        Text(
          'Video not found',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFF59D),
            foregroundColor: Colors.black,
          ),
          onPressed: _initializeVideo,
          child: Text(
            'Try Again',
            style: TextStyle(
              fontFamily: 'Lora-Regular',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Color.fromRGBO(0, 0, 0, 0.1),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Speed:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Lora-Regular',
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Lora-Regular',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, color: Colors.black),
                onSelected: _changePlaybackSpeed,
                itemBuilder: (context) => _speedOptions.map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text(
                      '${speed}x',
                      style: TextStyle(
                        fontFamily: 'Poppins-Regular',
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 30, color: Colors.black),
                onPressed: () {
                  final newPosition = _videoController.value.position - const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: Icon(
                  _videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 40,
                  color: Colors.black,
                ),
                onPressed: () {
                  setState(() {
                    if (_videoController.value.isPlaying) {
                      _videoController.pause();
                    } else {
                      _videoController.play();
                    }
                  });
                },
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 30, color: Colors.black),
                onPressed: () {
                  final newPosition = _videoController.value.position + const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              const SizedBox(width: 20),
              IconButton(
                icon: const Icon(Icons.replay, size: 30, color: Colors.black),
                onPressed: () {
                  _videoController.seekTo(Duration.zero);
                  _videoController.play();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// DICTIONARY SCREEN BUILDER
Widget _buildDictionaryScreen(BuildContext context, String title, Color color, 
    {String? videoAsset}) {
  return Scaffold(
    backgroundColor: Colors.white, // White background
    appBar: AppBar(
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          fontFamily: 'Lora-Regular',
          color: Colors.black,
        ),
      ),
      centerTitle: true,
      elevation: 0,
    ),
    body: Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA8D5E3),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.black, width: 1),
                ),
              ),
              onPressed: videoAsset != null ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DictionaryVideoScreen(
                    title: title,
                    videoAsset: videoAsset,
                    backgroundColor: const Color(0xFFA8D5E3),
                  )),
                );
              } : null,
              child: Text(
                'View Video ${videoAsset == null ? '(Coming Soon)' : ''}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Lora-Regular',
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library,
                    size: 60,
                    color: color,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'View the sign language video for "$title"',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'Poppins-Regular',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (videoAsset == null)
                    Text(
                      '(Video coming soon)',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Poppins-Regular',
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}


// ============ NUMBERS & OPERATORS DICTIONARY SCREEN (USING ACTUAL DATASET) ============
class NumbersOperatorsDictionaryScreen extends StatefulWidget {
  const NumbersOperatorsDictionaryScreen({super.key});

  @override
  State<NumbersOperatorsDictionaryScreen> createState() => _NumbersOperatorsDictionaryScreenState();
}

class _NumbersOperatorsDictionaryScreenState extends State<NumbersOperatorsDictionaryScreen> {
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Ones (0-9)', 'Tens', 'Hundreds', 'Thousands', 'Operators'];

  @override
  Widget build(BuildContext context) {
    final allSigns = SignLanguageService.getAllSigns();
    
    // Filter signs based on selected category
    Map<String, String> filteredSigns = {};
    if (_selectedCategory == 'All') {
      filteredSigns = allSigns;
    } else if (_selectedCategory == 'Ones (0-9)') {
      filteredSigns = Map.fromEntries(
        allSigns.entries.where((e) => e.key.contains('Number') && int.tryParse(e.key.split(' ').last) != null && int.parse(e.key.split(' ').last) < 10)
      );
    } else if (_selectedCategory == 'Tens') {
      filteredSigns = Map.fromEntries(
        allSigns.entries.where((e) => e.key.contains('Number') && e.key.split(' ').last.length == 2 && e.key.split(' ').last.endsWith('0'))
      );
    } else if (_selectedCategory == 'Hundreds') {
      filteredSigns = Map.fromEntries(
        allSigns.entries.where((e) => e.key.contains('Number') && e.key.split(' ').last.length == 3)
      );
    } else if (_selectedCategory == 'Thousands') {
      filteredSigns = Map.fromEntries(
        allSigns.entries.where((e) => e.key.contains('Number') && e.key.split(' ').last.length == 4)
      );
    } else if (_selectedCategory == 'Operators') {
      filteredSigns = Map.fromEntries(
        allSigns.entries.where((e) => !e.key.contains('Number'))
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Numbers & Operators',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Category filter
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = category == _selectedCategory;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCategory = category;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFEDA5F) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.grey[300]!,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        category,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: Colors.black,
                          fontFamily: 'Poppins-Regular',
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Grid of signs
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 0.85,
              ),
              itemCount: filteredSigns.length,
              itemBuilder: (context, index) {
                final entry = filteredSigns.entries.elementAt(index);
                return _buildSignCard(entry.key, entry.value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignCard(String label, String videoPath) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DictionaryVideoScreen(
              title: label,
              videoAsset: videoPath,
              backgroundColor: Colors.white,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFA8D5E3),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.play_circle_outline,
              size: 60,
              color: Colors.black54,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontFamily: 'Poppins-Regular',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



// INDIVIDUAL DICTIONARY SCREENS
class FractionDictionaryScreen extends StatelessWidget {
  const FractionDictionaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> fractionTerms = {
      'Fraction': 'assets/DataSet/Dictionary/sign-fraction.webm',
      'Numerator': 'assets/DataSet/Dictionary/sign-numerator.webm',
      'Denominator': 'assets/DataSet/Dictionary/sign-denominator.webm',
      'Decimal Number': 'assets/DataSet/Dictionary/sign-decimal-number.webm',
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Fraction',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 0.85,
        ),
        itemCount: fractionTerms.length,
        itemBuilder: (context, index) {
          final entry = fractionTerms.entries.elementAt(index);
          return _buildTermCard(context, entry.key, entry.value, const Color(0xFFA8D5E3));
        },
      ),
    );
  }
}

class AlgebraDictionaryScreen extends StatelessWidget {
  const AlgebraDictionaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> algebraTerms = {
      'Algebra': 'assets/DataSet/Dictionary/sign-algebra.webm',
      'Equation': 'assets/DataSet/Dictionary/sign-equation.webm',
      'Number Value': 'assets/DataSet/Dictionary/sign-number-value.webm',
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Algebra',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 0.85,
        ),
        itemCount: algebraTerms.length,
        itemBuilder: (context, index) {
          final entry = algebraTerms.entries.elementAt(index);
          return _buildTermCard(context, entry.key, entry.value, const Color(0xFF9C89B8));
        },
      ),
    );
  }
}

// Helper function to build term cards
Widget _buildTermCard(BuildContext context, String label, String videoPath, Color backgroundColor) {
  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DictionaryVideoScreen(
            title: label,
            videoAsset: videoPath,
            backgroundColor: Colors.white,
          ),
        ),
      );
    },
    child: Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.play_circle_outline,
            size: 60,
            color: Colors.black54,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontFamily: 'Poppins-Regular',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}


// ============ FRONT PAGE SCREEN ============
class FrontPageScreen extends StatefulWidget {
  const FrontPageScreen({super.key});

  @override
  State<FrontPageScreen> createState() => _FrontPageScreenState();
}

class _FrontPageScreenState extends State<FrontPageScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  // State for tracking which option is selected
  bool _isStudentSelected = false;
  bool _isSenyamatikardSelected = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    // Create slide animation (slides up from bottom)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0), // Start from bottom (off-screen)
      end: Offset.zero, // End at normal position
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );
    
    // Create fade animation
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
    
    // Delay the animation by 1.5 seconds then start
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Function to handle student selection
  void _selectStudent() {
    setState(() {
      _isStudentSelected = true;
      _isSenyamatikardSelected = false;
    });
  }

  // Function to handle teacher selection (Senyamatikard)
  void _selectSenyamatikard() {
    setState(() {
      _isStudentSelected = false;
      _isSenyamatikardSelected = true;
    });
  }

  // Function to launch Senyamatikard website
  // Update the IP address below to match your computer's WiFi IP
  Future<void> _launchSenyamatikard() async {
    final Uri url = Uri.parse('https://senyamatikard.vercel.app/');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot open website. Please check your connection.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Function to navigate back to main menu
  void _goBackToMain() {
    setState(() {
      _isStudentSelected = false;
      _isSenyamatikardSelected = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isVerySmallScreen = screenHeight < 600;
    final isTablet = screenWidth > 600;

    return Scaffold(
      backgroundColor: Colors.white, // White background
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // TITLE SECTION - Moved lower
                Padding(
                  padding: EdgeInsets.only(
                    top: isVerySmallScreen 
                        ? screenHeight * 0.12 
                        : screenHeight * 0.15,
                  ),
                  child: Center(
                    child: Stack(
                      children: [
                        // BORDER/STROKE TEXT
                        Text(
                          'SenyaMatika',
                          style: TextStyle(
                            fontSize: isVerySmallScreen
                                ? 34
                                : isTablet
                                    ? 56
                                    : 44,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Lora-Regular',
                            letterSpacing: 1.2,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 1.2
                              ..color = Colors.black,
                          ),
                        ),
                        // MAIN TEXT
                        Text(
                          'SenyaMatika',
                          style: TextStyle(
                            fontSize: isVerySmallScreen
                                ? 34
                                : isTablet
                                    ? 56
                                    : 44,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Lora-Regular',
                            color: Colors.black,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // IMAGE SECTION - Increased size
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: isVerySmallScreen ? 30 : 60,
                        horizontal: screenWidth * 0.1,
                      ),
                      child: Image.asset(
                        'assets/assetsmyimage.png',
                        fit: BoxFit.contain,
                        width: isVerySmallScreen
                            ? screenWidth * 0.8
                            : isTablet
                                ? screenWidth * 0.6
                                : screenWidth * 0.9,
                        height: isVerySmallScreen
                            ? screenWidth * 0.6
                            : isTablet
                                ? screenWidth * 0.4
                                : screenWidth * 0.7,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: isVerySmallScreen
                                ? screenWidth * 0.8
                                : isTablet
                                    ? screenWidth * 0.6
                                    : screenWidth * 0.9,
                            height: isVerySmallScreen
                                ? screenWidth * 0.6
                                : isTablet
                                    ? screenWidth * 0.4
                                    : screenWidth * 0.7,
                            color: Colors.white,
                            child: Center(
                              child: Icon(
                                Icons.image,
                                size: isSmallScreen ? 60 : 90,
                                color: const Color(0xFF007AFF),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // SPACER for the animated buttons (takes up the space)
                SizedBox(
                  height: isVerySmallScreen ? 170 : 200,
                ),
              ],
            ),

            // ANIMATED BUTTONS SECTION (will slide up)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.only(
                      bottom: isVerySmallScreen ? 40 : 60,
                      left: screenWidth * 0.1,
                      right: screenWidth * 0.1,
                      top: 30,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white, // White background
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 25,
                          spreadRadius: 5,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // CONDITIONAL RENDERING - Show options first
                        if (!_isStudentSelected && !_isSenyamatikardSelected)
                          Column(
                            children: [
                              // FOR STUDENT BUTTON
                              SizedBox(
                                width: double.infinity,
                                height: isVerySmallScreen
                                    ? screenHeight * 0.07
                                    : isTablet
                                        ? screenHeight * 0.09
                                        : screenHeight * 0.08,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFEDA5E),
                                    foregroundColor: Colors.black,
                                    elevation: 5,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      side: const BorderSide(
                                        color: Colors.black,
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                  onPressed: _selectStudent,
                                  child: Text(
                                    'For Student',
                                    style: TextStyle(
                                      fontSize: isVerySmallScreen
                                          ? 17
                                          : isTablet
                                              ? 24
                                              : 21,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Lora-Regular',
                                    ),
                                  ),
                                ),
                              ),

                              SizedBox(height: isVerySmallScreen ? 18 : 25),

                              // FOR TEACHERS BUTTON (formerly Senyamatikard)
                              SizedBox(
                                width: double.infinity,
                                height: isVerySmallScreen
                                    ? screenHeight * 0.07
                                    : isTablet
                                        ? screenHeight * 0.09
                                        : screenHeight * 0.08,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD4E8FF),
                                    foregroundColor: Colors.black,
                                    elevation: 5,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      side: const BorderSide(
                                        color: Colors.black,
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                  onPressed: _selectSenyamatikard,
                                  child: Text(
                                    'For Teachers',
                                    style: TextStyle(
                                      fontSize: isVerySmallScreen
                                          ? 17
                                          : isTablet
                                              ? 24
                                              : 21,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Lora-Regular',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                        // SHOW CREATE ACCOUNT AND LOG IN BUTTONS AFTER STUDENT IS SELECTED
                        if (_isStudentSelected)
                          Column(
                            children: [
                              // BACK BUTTON
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _goBackToMain,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          border: Border.all(color: Colors.black, width: 1),
                                        ),
                                        child: const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Icon(
                                            Icons.arrow_back,
                                            color: Colors.black,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 15),
                                    Text(
                                      'For Student',
                                      style: TextStyle(
                                        fontSize: isVerySmallScreen
                                            ? 20
                                            : isTablet
                                                ? 28
                                                : 24,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Lora-Regular',
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // CREATE ACCOUNT BUTTON
                              SizedBox(
                                width: double.infinity,
                                height: isVerySmallScreen
                                    ? screenHeight * 0.07
                                    : isTablet
                                        ? screenHeight * 0.09
                                        : screenHeight * 0.08,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFEDA5E),
                                    foregroundColor: Colors.black,
                                    elevation: 5,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      side: const BorderSide(
                                        color: Colors.black,
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const CreateAccountScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: isVerySmallScreen
                                          ? 17
                                          : isTablet
                                              ? 24
                                              : 21,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Lora-Regular',
                                    ),
                                  ),
                                ),
                              ),

                              SizedBox(height: isVerySmallScreen ? 18 : 25),

                              // LOG IN BUTTON
                              SizedBox(
                                width: double.infinity,
                                height: isVerySmallScreen
                                    ? screenHeight * 0.07
                                    : isTablet
                                        ? screenHeight * 0.09
                                        : screenHeight * 0.08,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD4E8FF),
                                    foregroundColor: Colors.black,
                                    elevation: 5,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      side: const BorderSide(
                                        color: Colors.black,
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const LogInScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontSize: isVerySmallScreen
                                          ? 17
                                          : isTablet
                                              ? 24
                                              : 21,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Lora-Regular',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                        // SHOW TEACHER OPTIONS WHEN "FOR TEACHERS" IS SELECTED
                        if (_isSenyamatikardSelected)
                          Column(
                            children: [
                              // BACK BUTTON
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _goBackToMain,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          border: Border.all(color: Colors.black, width: 1),
                                        ),
                                        child: const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Icon(
                                            Icons.arrow_back,
                                            color: Colors.black,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 15),
                                    Text(
                                      'Teacher Tools',
                                      style: TextStyle(
                                        fontSize: isVerySmallScreen
                                            ? 20
                                            : isTablet
                                                ? 28
                                                : 24,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Lora-Regular',
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // TEACHER OPTIONS CONTAINER
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: Colors.green, width: 2),
                                ),
                                child: Column(
                                  children: [
                                    // Option 1: Sign Language Avatar
                                    SizedBox(
                                      width: double.infinity,
                                      height: isVerySmallScreen
                                          ? screenHeight * 0.07
                                          : isTablet
                                              ? screenHeight * 0.09
                                              : screenHeight * 0.08,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFA8D5E3),
                                          foregroundColor: Colors.black,
                                          elevation: 5,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(18),
                                            side: const BorderSide(
                                              color: Colors.black,
                                              width: 2.5,
                                            ),
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => const SignLanguageAvatarScreen(),
                                            ),
                                          );
                                        },
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.face,
                                              size: isVerySmallScreen ? 20 : 24,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Sign Language Avatar',
                                              style: TextStyle(
                                                fontSize: isVerySmallScreen
                                                    ? 14
                                                    : isTablet
                                                        ? 20
                                                        : 16,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Lora-Regular',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    
                                    const SizedBox(height: 15),

                                    // Option 2: Senyamatikard Website
                                    SizedBox(
                                      width: double.infinity,
                                      height: isVerySmallScreen
                                          ? screenHeight * 0.07
                                          : isTablet
                                              ? screenHeight * 0.09
                                              : screenHeight * 0.08,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFFFF59D),
                                          foregroundColor: Colors.black,
                                          elevation: 5,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(18),
                                            side: const BorderSide(
                                              color: Colors.black,
                                              width: 2.5,
                                            ),
                                          ),
                                        ),
                                        onPressed: _launchSenyamatikard,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.language,
                                              size: isVerySmallScreen ? 20 : 24,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Senyamatikard (Web)',
                                              style: TextStyle(
                                                fontSize: isVerySmallScreen
                                                    ? 14
                                                    : isTablet
                                                        ? 20
                                                        : 16,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Lora-Regular',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 15),

                                    // Additional info text
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Choose a tool to demonstrate sign language or access the web platform.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: isVerySmallScreen ? 11 : 13,
                                          fontFamily: 'Poppins-Regular',
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ============ CREATE ACCOUNT SCREEN ============
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _otherSchoolController = TextEditingController();
  final TextEditingController _otherGradeController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();
  final LocalAuthService _authService = LocalAuthService();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  final List<String> _schools = [
    'None',
    'San Miguel National HighSchool',
    'Bajet-Castillo High School',
    'Pulong Buhangin National High School',
    'Others',
  ];

  final List<String> _gradeOptions = [
    'Grade 7',
    'Grade 8',
    'Grade 9',
    'Grade 10',
    'Non-graded',
    'Others',
  ];

  String? _selectedSchool;
  String? _selectedGrade;

  String? get _finalSchool {
    if (_selectedSchool == 'Others') {
      final typed = _otherSchoolController.text.trim();
      return typed.isEmpty ? null : typed;
    }
    return _selectedSchool;
  }

  String? get _finalSection {
    final grade = _selectedGrade;
    final classSection = _sectionController.text.trim();

    String? actualGrade;
    if (grade == 'Others') {
      final typed = _otherGradeController.text.trim();
      actualGrade = typed.isEmpty ? null : typed;
    } else {
      actualGrade = grade;
    }

    if (actualGrade == null) return null;
    if (classSection.isNotEmpty && classSection != 'None') {
      return '$actualGrade - $classSection';
    }
    return actualGrade;
  }

  Future<void> _createAccount() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final school = _finalSchool;
    final section = _finalSection;

    if (firstName.isEmpty) {
      _showSnackbar('Please enter your first name', Colors.red);
      return;
    }
    if (lastName.isEmpty) {
      _showSnackbar('Please enter your last name', Colors.red);
      return;
    }
    if (email.isEmpty) {
      _showSnackbar('Please enter your email', Colors.red);
      return;
    }
    if (!email.endsWith('@gmail.com')) {
      _showSnackbar('Please use a valid Gmail address (@gmail.com)', Colors.red);
      return;
    }
    if (password.isEmpty) {
      _showSnackbar('Please enter a password', Colors.red);
      return;
    }
    if (password.length < 6) {
      _showSnackbar('Password must be at least 6 characters', Colors.red);
      return;
    }
    if (password != confirmPassword) {
      _showSnackbar('Passwords do not match', Colors.red);
      return;
    }
    if (_selectedSchool == null) {
      _showSnackbar('Please select your school', Colors.red);
      return;
    }
    if (_selectedSchool == 'Others' &&
        _otherSchoolController.text.trim().isEmpty) {
      _showSnackbar('Please enter your school name', Colors.red);
      return;
    }
    if (_selectedGrade == null) {
      _showSnackbar('Please select your Grade Level', Colors.red);
      return;
    }
    if (_selectedGrade == 'Others' &&
        _otherGradeController.text.trim().isEmpty) {
      _showSnackbar('Please enter your grade level', Colors.red);
      return;
    }
    if (_sectionController.text.trim().isEmpty) {
      _showSnackbar(
          'Please enter your Class / Section (type "None" if not applicable)',
          Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fullName = '$firstName $lastName';

      final user = await _authService.registerWithEmail(
        email: email,
        password: password,
        name: fullName,
        school: school,
        section: section,
      );

      if (user != null) {
        // Sync to Railway backend
       try {
          final sectionOnly = _sectionController.text.trim();
          final gradeOnly = _selectedGrade == 'Others'
              ? _otherGradeController.text.trim()
              : _selectedGrade ?? '';
          final schoolFinal = _selectedSchool == 'Others'
              ? _otherSchoolController.text.trim()
              : _selectedSchool ?? '';
          await ApiService.register(
            email: email,
            password: password,
            name: fullName,
            school: schoolFinal,
            section: '$gradeOnly - $sectionOnly',
          );
        } catch (e) {
          print('Backend sync error: $e');
        }

        UserProvider.setUser(UserData(
          name: fullName,
          email: email,
          school: school,
          section: section,
        ));

        progressManager.setCurrentUser(user.uid);

        if (mounted) {
          _showSnackbar('Account created successfully!', Colors.green);

          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const DashboardScreen()),
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar(
          e.toString().replaceAll('Exception: ', ''),
          Colors.red,
        );
      }
    }
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Poppins-Regular'),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                ),
              ),
            ),

            SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Center(
                    child: Text(
                      'Welcome to SenyaMatika!',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Lora-Regular',
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Lora-Regular',
                          color: Colors.black,
                          height: 0.9,
                        ),
                      ),
                      Text(
                        'Account',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Lora-Regular',
                          color: Colors.black,
                          height: 0.9,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB0BDC1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTextField(
                          controller: _firstNameController,
                          label: 'First Name:',
                          hintText: 'Enter your first name',
                          prefixIcon: Icons.person,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 20),

                        _buildTextField(
                          controller: _lastNameController,
                          label: 'Last Name:',
                          hintText: 'Enter your last name',
                          prefixIcon: Icons.person_outline,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 20),

                        _buildDropdownField(
                          label: 'School:',
                          hintText: 'Choose your school',
                          prefixIcon: Icons.school,
                          value: _selectedSchool,
                          items: _schools.map((school) {
                            return DropdownMenuItem<String>(
                              value: school,
                              child: Text(
                                school,
                                style: const TextStyle(
                                    fontFamily: 'Poppins-Regular'),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedSchool = value;
                              if (value != 'Others') {
                                _otherSchoolController.clear();
                              }
                            });
                          },
                        ),

                        if (_selectedSchool == 'Others') ...[
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _otherSchoolController,
                            label: 'Enter your school name:',
                            hintText: 'Type your school name here',
                            prefixIcon: Icons.edit_location_alt,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ],
                        const SizedBox(height: 20),

                        _buildDropdownField(
                          label: 'Grade Level:',
                          hintText: 'Choose your grade level',
                          prefixIcon: Icons.group,
                          value: _selectedGrade,
                          items: _gradeOptions.map((grade) {
                            return DropdownMenuItem<String>(
                              value: grade,
                              child: Text(
                                grade,
                                style: const TextStyle(
                                    fontFamily: 'Poppins-Regular'),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedGrade = value;
                              if (value != 'Others') {
                                _otherGradeController.clear();
                              }
                            });
                          },
                        ),

                        if (_selectedGrade == 'Others') ...[
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _otherGradeController,
                            label: 'Enter your grade level:',
                            hintText: 'Type your grade level here',
                            prefixIcon: Icons.edit,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ],
                        const SizedBox(height: 20),

                        _buildTextField(
                          controller: _sectionController,
                          label: 'Class / Section:',
                          hintText:
                              'e.g. Sampaguita, Section A — type "None" if not applicable',
                          prefixIcon: Icons.class_,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 20),

                        _buildTextField(
                          controller: _emailController,
                          label: 'Email:',
                          hintText: 'Enter your Gmail address (@gmail.com)',
                          prefixIcon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 20),

                        _buildPasswordField(
                          controller: _passwordController,
                          label: 'Password:',
                          hintText: 'Enter your password',
                          isPasswordVisible: _isPasswordVisible,
                          onToggleVisibility: () {
                            setState(() =>
                                _isPasswordVisible = !_isPasswordVisible);
                          },
                        ),
                        const SizedBox(height: 20),

                        _buildPasswordField(
                          controller: _confirmPasswordController,
                          label: 'Confirm Password:',
                          hintText: 'Confirm your password',
                          isPasswordVisible: _isConfirmPasswordVisible,
                          onToggleVisibility: () {
                            setState(() => _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible);
                          },
                        ),
                        const SizedBox(height: 35),

                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFEDA5E),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                    color: Colors.black, width: 2),
                              ),
                              elevation: 5,
                              shadowColor: Colors.black.withOpacity(0.2),
                            ),
                            onPressed: _isLoading ? null : _createAccount,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.black),
                                    ),
                                  )
                                : Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Lora-Regular',
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
              hintText: hintText,
              hintStyle: TextStyle(
                  fontFamily: 'Poppins-Regular', color: Colors.grey[600]),
              border: InputBorder.none,
              prefixIcon: Icon(prefixIcon, color: Colors.black),
              filled: true,
              fillColor: Colors.transparent,
            ),
            style: const TextStyle(
              fontFamily: 'Poppins-Regular',
              fontSize: 16,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String hintText,
    required IconData prefixIcon,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                hint: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    hintText,
                    style: TextStyle(
                        fontFamily: 'Poppins-Regular',
                        color: Colors.grey[600]),
                  ),
                ),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
                iconSize: 30,
                isExpanded: true,
                style: const TextStyle(
                  fontFamily: 'Poppins-Regular',
                  fontSize: 16,
                  color: Colors.black,
                ),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required bool isPasswordVisible,
    required VoidCallback onToggleVisibility,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: !isPasswordVisible,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
              hintText: hintText,
              hintStyle: TextStyle(
                  fontFamily: 'Poppins-Regular', color: Colors.grey[600]),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.lock, color: Colors.black),
              suffixIcon: IconButton(
                icon: Icon(
                  isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.black,
                ),
                onPressed: onToggleVisibility,
              ),
              filled: true,
              fillColor: Colors.transparent,
            ),
            style: const TextStyle(
              fontFamily: 'Poppins-Regular',
              fontSize: 16,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}

// ============ LOG IN SCREEN (WITHOUT PICTURE) ============
class LogInScreen extends StatefulWidget {
  const LogInScreen({super.key});

  @override
  State<LogInScreen> createState() => _LogInScreenState();
}

class _LogInScreenState extends State<LogInScreen> {
  // ADD THESE CONTROLLERS
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final LocalAuthService _authService = LocalAuthService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  Future<void> _logIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter your email',
            style: TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // DAGDAG: Validation para siguraduhing may @gmail.com ang email
    if (!email.endsWith('@gmail.com')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please use a valid Gmail address (@gmail.com)',
            style: TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter your password',
            style: TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading
    setState(() {
      _isLoading = true;
    });

    try {
      // Use local authentication
      // Note: Students authenticate via student ID provided by teacher for backend sync
      final user = await _authService.signInWithEmail(
        email: email,
        password: password,
      );

      if (user != null) {
        // Set user in provider
        UserProvider.setUser(UserData(
          name: user.name,
          email: user.email,
          school: user.school,
          section: user.section,
        ));

        // Set current user for progress tracking
        progressManager.setCurrentUser(user.uid);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Logged in successfully!',
                style: TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const DashboardScreen()),
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceAll('Exception: ', ''),
              style: TextStyle(fontFamily: 'Poppins-Regular'),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      body: SafeArea(
        child: Stack(
          children: [
            // Background decorative elements (same as CreateAccountScreen)
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                ),
              ),
            ),
            
            SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button at top left
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Welcome text - CENTERED
                  Center(
                    child: Text(
                      'Welcome Back!',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Lora-Regular',
                        color: Colors.black,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // Sign in text - CENTERED
                  Center(
                    child: Text(
                      'Sign In to continue',
                      style: TextStyle(
                        fontSize: 18,
                        fontFamily: 'Poppins-Regular',
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // REMOVED THE IMAGE - Now just the title
                  Container(
                    width: double.infinity,
                    child: Text(
                      'Log In',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Lora-Regular',
                        color: Colors.black,
                      ),
                    ),
                  ),
                  
                  // Divider line
                  Container(
                    margin: const EdgeInsets.only(top: 5, bottom: 30),
                    height: 2,
                    color: Colors.grey[300],
                  ),
                  
                  // Log In card (BOX NA KULAY B0BDC1)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB0BDC1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Form fields
                        _buildTextField(
                          controller: _emailController,
                          label: 'Email:',
                          hintText: 'Enter your Gmail address (@gmail.com)',
                          prefixIcon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 20),
                        
                        _buildPasswordField(
                          controller: _passwordController,
                          label: 'Password:',
                          hintText: 'Enter your password',
                          isPasswordVisible: _isPasswordVisible,
                          onToggleVisibility: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        
                        // Forgot Password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                              );
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Poppins-Regular',
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 35),
                        
                        // Log In Button
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFEDA5E),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 2,
                                ),
                              ),
                              elevation: 5,
                              shadowColor: Colors.black.withOpacity(0.2),
                            ),
                            onPressed: _isLoading ? null : _logIn,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                    ),
                                  )
                                : Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Lora-Regular',
                                    ),
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Don't have an account? Sign up
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'Poppins-Regular',
                            color: Colors.black87,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const CreateAccountScreen()),
                            );
                          },
                          child: Text(
                            'Sign up',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Poppins-Regular',
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.black,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
              hintText: hintText,
              hintStyle: TextStyle(
                fontFamily: 'Poppins-Regular',
                color: Colors.grey[600],
              ),
              border: InputBorder.none,
              prefixIcon: Icon(prefixIcon, color: Colors.black),
              filled: true,
              fillColor: Colors.transparent,
            ),
            style: TextStyle(
              fontFamily: 'Poppins-Regular',
              fontSize: 16,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required bool isPasswordVisible,
    required VoidCallback onToggleVisibility,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.black,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: !isPasswordVisible,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
              hintText: hintText,
              hintStyle: TextStyle(
                fontFamily: 'Poppins-Regular',
                color: Colors.grey[600],
              ),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.lock, color: Colors.black),
              suffixIcon: IconButton(
                icon: Icon(
                  isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.black,
                ),
                onPressed: onToggleVisibility,
              ),
              filled: true,
              fillColor: Colors.transparent,
            ),
            style: TextStyle(
              fontFamily: 'Poppins-Regular',
              fontSize: 16,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}


// ============ PROFILE SCREEN ============
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isDrawerOpen = false;

  void _toggleDrawer() {
    setState(() {
      _isDrawerOpen = !_isDrawerOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Main Content
          Column(
            children: [
              // App Bar with Back Button Only
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Lora-Regular',
                        color: Colors.black,
                      ),
                    ),
                    Container(width: 48),
                  ],
                ),
              ),

              const Divider(height: 1, color: Colors.grey),

              // User Info
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 50),
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[300],
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        UserProvider.getUserName(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Lora-Regular',
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        UserProvider.getUserEmail(),
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'Poppins-Regular',
                          color: Colors.grey[700],
                        ),
                      ),

                      // School and Section Info
                      if (UserProvider.getUserSchool() != null)
                        Column(
                          children: [
                            const SizedBox(height: 15),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${UserProvider.getUserSchool()}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Poppins-Regular',
                                      color: Colors.blue[900],
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${UserProvider.getUserSection()}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontFamily: 'Poppins-Regular',
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 40),

                      // Edit Profile Button — FIXED: .then() forces rebuild
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFEDA5E),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(
                                  color: Colors.black, width: 2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 5,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const EditProfileScreen()),
                            ).then((_) {
                              // Force ProfileScreen to rebuild so new
                              // name / school / section show immediately
                              if (mounted) setState(() {});
                            });
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.edit, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                'Edit Profile',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Lora-Regular',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Account Information Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.grey.shade300, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Account Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Lora-Regular',
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildInfoRow(
                                'Full Name:', UserProvider.getUserName()),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                                'Email:', UserProvider.getUserEmail()),
                            if (UserProvider.getUserSchool() != null) ...[
                              const SizedBox(height: 8),
                              _buildInfoRow('School:',
                                  UserProvider.getUserSchool()!),
                            ],
                            if (UserProvider.getUserSection() != null) ...[
                              const SizedBox(height: 8),
                              _buildInfoRow('Grade level:',
                                  UserProvider.getUserSection()!),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Overlay when drawer is open
          if (_isDrawerOpen)
            GestureDetector(
              onTap: _toggleDrawer,
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),

          // Side Drawer
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            right: _isDrawerOpen ? 0 : -300,
            top: 0,
            bottom: 0,
            child: Container(
              width: 300,
              color: Colors.white,
              child: Column(
                children: [
                  Container(
                    height: 120,
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          UserProvider.getUserName(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Lora-Regular',
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          UserProvider.getUserEmail(),
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'Poppins-Regular',
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildDrawerMenuItem(
                          title: 'Edit Profile',
                          icon: Icons.edit,
                          onTap: () {
                            _toggleDrawer();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const EditProfileScreen()),
                            ).then((_) {
                              if (mounted) setState(() {});
                            });
                          },
                        ),
                        const SizedBox(height: 15),
                        _buildDrawerMenuItem(
                          title: 'Settings',
                          icon: Icons.settings,
                          onTap: () {
                            _toggleDrawer();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const SettingsScreen()),
                            );
                          },
                        ),
                        const SizedBox(height: 15),
                        _buildDrawerMenuItem(
                          title: 'Help',
                          icon: Icons.help_outline,
                          onTap: () {
                            _toggleDrawer();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const HelpScreen()),
                            );
                          },
                        ),
                        const SizedBox(height: 15),
                        _buildDrawerMenuItem(
                          title: 'About',
                          icon: Icons.info_outline,
                          onTap: () {
                            _toggleDrawer();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const AboutScreen()),
                            );
                          },
                        ),
                        const SizedBox(height: 30),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 30),
                        _buildLogOutButton(context),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 30, color: Colors.black),
                      onPressed: _toggleDrawer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontFamily: 'Poppins-Regular',
            color: Colors.black87,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.blue[700],
          ),
        ),
      ],
    );
  }

  Widget _buildDrawerMenuItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.black, size: 24),
              const SizedBox(width: 15),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Lora-Regular',
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogOutButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _toggleDrawer();
          UserProvider.setUser(UserData(name: '', email: ''));
          progressManager.setCurrentUser(null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sign out successfully',
                style: TextStyle(
                  fontFamily: 'Poppins-Regular',
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (context) => const FrontPageScreen()),
              (route) => false,
            );
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.red.shade700, size: 24),
              const SizedBox(width: 15),
              Text(
                'Logout',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Lora-Regular',
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ============ FIXED EDIT PROFILE SCREEN ============
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController  = TextEditingController();
  final TextEditingController _emailController     = TextEditingController();
  final TextEditingController _passwordController  = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _otherSchoolController = TextEditingController();
  final TextEditingController _otherGradeController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();

  bool _isPasswordVisible        = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading                = false;

  final List<String> _schools = [
    'None',
    'San Miguel National HighSchool',
    'Bajet-Castillo High School',
    'Pulong Buhangin National High School',
    'Others',
  ];

  final List<String> _gradeOptions = [
    'Grade 7',
    'Grade 8',
    'Grade 9',
    'Grade 10',
    'Non-graded',
    'Others',
  ];

  String? _selectedSchool;
  String? _selectedGrade;

  String? get _finalSchool {
    if (_selectedSchool == 'Others') {
      final typed = _otherSchoolController.text.trim();
      return typed.isEmpty ? null : typed;
    }
    return _selectedSchool;
  }

  String? get _finalSection {
    final grade = _selectedGrade;
    final classSection = _sectionController.text.trim();

    String? actualGrade;
    if (grade == 'Others') {
      final typed = _otherGradeController.text.trim();
      actualGrade = typed.isEmpty ? null : typed;
    } else {
      actualGrade = grade;
    }

    if (actualGrade == null) return null;
    if (classSection.isNotEmpty && classSection != 'None') {
      return '$actualGrade - $classSection';
    }
    return actualGrade;
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final currentName    = UserProvider.getUserName();
    final currentEmail   = UserProvider.getUserEmail();
    final currentSchool  = UserProvider.getUserSchool();
    final currentSection = UserProvider.getUserSection();

    final nameParts = currentName.split(' ');
    if (nameParts.length >= 2) {
      _firstNameController.text = nameParts.first;
      _lastNameController.text  = nameParts.sublist(1).join(' ');
    } else {
      _firstNameController.text = currentName;
    }

    _emailController.text = currentEmail;

    setState(() {
      // Restore school
      if (currentSchool != null && _schools.contains(currentSchool)) {
        _selectedSchool = currentSchool;
      } else if (currentSchool != null && currentSchool.isNotEmpty) {
        _selectedSchool = 'Others';
        _otherSchoolController.text = currentSchool;
      } else {
        _selectedSchool = null;
      }

      // Restore grade level and class/section
      if (currentSection != null && currentSection.isNotEmpty) {
        if (currentSection.contains(' - ')) {
          final parts = currentSection.split(' - ');
          final grade = parts[0].trim();
          final classSection = parts.sublist(1).join(' - ').trim();

          if (_gradeOptions.contains(grade)) {
            _selectedGrade = grade;
          } else {
            // Was a custom grade typed via "Others"
            _selectedGrade = 'Others';
            _otherGradeController.text = grade;
          }
          _sectionController.text = classSection;
        } else {
          final grade = currentSection.trim();
          if (_gradeOptions.contains(grade)) {
            _selectedGrade = grade;
          } else {
            // Was a custom grade typed via "Others"
            _selectedGrade = 'Others';
            _otherGradeController.text = grade;
          }
          _sectionController.text = '';
        }
      }
    });
  }

  Future<void> _saveProfile() async {
    final firstName       = _firstNameController.text.trim();
    final lastName        = _lastNameController.text.trim();
    final email           = _emailController.text.trim();
    final password        = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final school          = _finalSchool;
    final section         = _finalSection;

    if (firstName.isEmpty) {
      _showErrorSnackbar('Please enter your first name');
      return;
    }
    if (lastName.isEmpty) {
      _showErrorSnackbar('Please enter your last name');
      return;
    }
    if (email.isEmpty) {
      _showErrorSnackbar('Please enter your email');
      return;
    }
    if (!email.endsWith('@gmail.com')) {
      _showErrorSnackbar('Please use a valid Gmail address (@gmail.com)');
      return;
    }
    if (password.isNotEmpty) {
      if (password.length < 6) {
        _showErrorSnackbar('Password must be at least 6 characters');
        return;
      }
      if (password != confirmPassword) {
        _showErrorSnackbar('Passwords do not match');
        return;
      }
    }
    if (_selectedSchool == null) {
      _showErrorSnackbar('Please select your school');
      return;
    }
    if (_selectedSchool == 'Others' &&
        _otherSchoolController.text.trim().isEmpty) {
      _showErrorSnackbar('Please enter your school name');
      return;
    }
    if (_selectedGrade == null) {
      _showErrorSnackbar('Please select your Grade Level');
      return;
    }
    if (_selectedGrade == 'Others' &&
        _otherGradeController.text.trim().isEmpty) {
      _showErrorSnackbar('Please enter your grade level');
      return;
    }
    if (_sectionController.text.trim().isEmpty) {
      _showErrorSnackbar(
          'Please enter your Class / Section (type "None" if not applicable)');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fullName = '$firstName $lastName';

      final authService = LocalAuthService();
      await authService.updateUserProfile(
        email: email,
        name: fullName,
        school: school,
        section: section,
      );

      if (password.isNotEmpty) {
        await authService.resetPassword(email, password);
        debugPrint('✅ Password updated in Hive');
      }

      UserProvider.updateUserInfo(
        name: fullName,
        email: email,
        school: school,
        section: section,
      );

      if (mounted) {
        final userProvider =
            Provider.of<backend.UserProvider>(context, listen: false);
        await userProvider.updateUserInfo(
          name: fullName,
          school: school,
          section: section,
        );
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Profile updated successfully!',
              style: TextStyle(
                fontFamily: 'Poppins-Regular',
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackbar('Failed to update profile: $e');
      }
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Poppins-Regular'),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                ),
              ),
            ),

            SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Center(
                    child: Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Lora-Regular',
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Center(
                    child: Text(
                      'Update your personal information',
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: 'Poppins-Regular',
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Heading
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Lora-Regular',
                          color: Colors.black,
                          height: 0.9,
                        ),
                      ),
                      Text(
                        'Profile',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Lora-Regular',
                          color: Colors.black,
                          height: 0.9,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Form card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB0BDC1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // First Name
                        _buildTextField(
                          controller: _firstNameController,
                          label: 'First Name:',
                          hintText: 'Enter your first name',
                          prefixIcon: Icons.person,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 20),

                        // Last Name
                        _buildTextField(
                          controller: _lastNameController,
                          label: 'Last Name:',
                          hintText: 'Enter your last name',
                          prefixIcon: Icons.person_outline,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 20),

                        // School dropdown
                        _buildDropdownField(
                          label: 'School:',
                          hintText: 'Select your school',
                          prefixIcon: Icons.school,
                          value: _selectedSchool,
                          items: _schools
                              .map((school) => DropdownMenuItem<String>(
                                    value: school,
                                    child: Text(
                                      school,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins-Regular'),
                                    ),
                                  ))
                              .toList(),
                          onChanged: _isLoading
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedSchool = value;
                                    if (value != 'Others') {
                                      _otherSchoolController.clear();
                                    }
                                  });
                                },
                        ),

                        // Others school text field
                        if (_selectedSchool == 'Others') ...[
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _otherSchoolController,
                            label: 'Enter your school name:',
                            hintText: 'Type your school name here',
                            prefixIcon: Icons.edit_location_alt,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Grade Level dropdown
                        _buildDropdownField(
                          label: 'Grade Level:',
                          hintText: 'Select your grade level',
                          prefixIcon: Icons.group,
                          value: _selectedGrade,
                          items: _gradeOptions
                              .map((grade) => DropdownMenuItem<String>(
                                    value: grade,
                                    child: Text(
                                      grade,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins-Regular'),
                                    ),
                                  ))
                              .toList(),
                          onChanged: _isLoading
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedGrade = value;
                                    if (value != 'Others') {
                                      _otherGradeController.clear();
                                    }
                                  });
                                },
                        ),

                        // Others grade text field
                        if (_selectedGrade == 'Others') ...[
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _otherGradeController,
                            label: 'Enter your grade level:',
                            hintText: 'Type your grade level here',
                            prefixIcon: Icons.edit,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Class / Section
                        _buildTextField(
                          controller: _sectionController,
                          label: 'Class / Section:',
                          hintText:
                              'e.g. Sampaguita, Section A — type "None" if not applicable',
                          prefixIcon: Icons.class_,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 20),

                        // Email
                        _buildTextField(
                          controller: _emailController,
                          label: 'Email:',
                          hintText: 'Enter your Gmail address',
                          prefixIcon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 20),

                        // New Password
                        _buildPasswordField(
                          controller: _passwordController,
                          label: 'New Password (optional):',
                          hintText:
                              'Enter new password (leave empty to keep current)',
                          isPasswordVisible: _isPasswordVisible,
                          onToggleVisibility: () {
                            setState(() =>
                                _isPasswordVisible = !_isPasswordVisible);
                          },
                        ),
                        const SizedBox(height: 20),

                        // Confirm Password
                        _buildPasswordField(
                          controller: _confirmPasswordController,
                          label: 'Confirm Password:',
                          hintText: 'Confirm your new password',
                          isPasswordVisible: _isConfirmPasswordVisible,
                          onToggleVisibility: () {
                            setState(() => _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible);
                          },
                        ),
                        const SizedBox(height: 35),

                        // Save Button
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFEDA5E),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                    color: Colors.black, width: 2),
                              ),
                              elevation: 5,
                              shadowColor: Colors.black.withOpacity(0.2),
                            ),
                            onPressed: _isLoading ? null : _saveProfile,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.black),
                                    ),
                                  )
                                : Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Lora-Regular',
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
              hintText: hintText,
              hintStyle: TextStyle(
                  fontFamily: 'Poppins-Regular', color: Colors.grey[600]),
              border: InputBorder.none,
              prefixIcon: Icon(prefixIcon, color: Colors.black),
              filled: true,
              fillColor: Colors.transparent,
            ),
            style: const TextStyle(
              fontFamily: 'Poppins-Regular',
              fontSize: 16,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String hintText,
    required IconData prefixIcon,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required Function(String?)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(prefixIcon, color: Colors.black),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: value,
                      hint: Text(
                        hintText,
                        style: TextStyle(
                            fontFamily: 'Poppins-Regular',
                            color: Colors.grey[600]),
                      ),
                      icon: const Icon(Icons.arrow_drop_down,
                          color: Colors.black),
                      iconSize: 30,
                      isExpanded: true,
                      style: const TextStyle(
                        fontFamily: 'Poppins-Regular',
                        fontSize: 16,
                        color: Colors.black,
                      ),
                      items: items,
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required bool isPasswordVisible,
    required VoidCallback onToggleVisibility,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: TextField(
            controller: controller,
            obscureText: !isPasswordVisible,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
              hintText: hintText,
              hintStyle: TextStyle(
                  fontFamily: 'Poppins-Regular', color: Colors.grey[600]),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.lock, color: Colors.black),
              suffixIcon: IconButton(
                icon: Icon(
                  isPasswordVisible
                      ? Icons.visibility
                      : Icons.visibility_off,
                  color: Colors.black,
                ),
                onPressed: onToggleVisibility,
              ),
              filled: true,
              fillColor: Colors.transparent,
            ),
            style: const TextStyle(
              fontFamily: 'Poppins-Regular',
              fontSize: 16,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}

// ============ UPDATED FORGOT PASSWORD SCREEN - ACTUALLY RESETS PASSWORD ============
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _emailVerified = false;
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  Future<void> _verifyEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showSnackbar('Please enter your email address', Colors.red);
      return;
    }

    if (!email.endsWith('@gmail.com')) {
      _showSnackbar('Please use a valid Gmail address (@gmail.com)', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if email exists in database
      final storage = LocalStorageService();
      final user = await storage.getUserByEmail(email);
      
      if (user == null) {
        _showSnackbar('No account found with this email', Colors.red);
        setState(() => _isLoading = false);
        return;
      }

      // Email verified - show password reset fields
      setState(() {
        _emailVerified = true;
        _isLoading = false;
      });
      
      _showSnackbar('Email verified! Enter your new password.', Colors.green);
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackbar('Error verifying email: $e', Colors.red);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.isEmpty) {
      _showSnackbar('Please enter a new password', Colors.red);
      return;
    }

    if (newPassword.length < 6) {
      _showSnackbar('Password must be at least 6 characters', Colors.red);
      return;
    }

    if (newPassword != confirmPassword) {
      _showSnackbar('Passwords do not match', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Reset password using LocalAuthService
      final authService = LocalAuthService();
      await authService.resetPassword(email, newPassword);

      _showSnackbar('Password reset successfully!', Colors.green);

      // Navigate back to login after delay
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackbar('Error resetting password: $e', Colors.red);
    }
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Background decorative elements
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                ),
              ),
            ),
            
            SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Title
                  Center(
                    child: Text(
                      _emailVerified ? 'Reset Password' : 'Forgot Password?',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Lora-Regular',
                        color: Colors.black,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // Instruction text
                  Center(
                    child: Text(
                      _emailVerified 
                          ? 'Enter your new password below'
                          : 'Enter your Gmail to reset your password',
                      style: TextStyle(
                        fontSize: 18,
                        fontFamily: 'Poppins-Regular',
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Title text
                  SizedBox(
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _emailVerified ? 'New' : 'Forgot',
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Lora-Regular',
                                color: Colors.black,
                                height: 0.9,
                              ),
                            ),
                            Text(
                              'Password',
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Lora-Regular',
                                color: Colors.black,
                                height: 0.9,
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: -10,
                          right: 0,
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: Image.asset(
                              'assets/images/child_hello.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.child_care, size: 40, color: Colors.black);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Form card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB0BDC1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email field (always shown)
                        _buildTextField(
                          controller: _emailController,
                          label: 'Gmail Address:',
                          hintText: 'Enter your Gmail address (@gmail.com)',
                          prefixIcon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_emailVerified,
                        ),
                        
                        // Password fields (shown after email verification)
                        if (_emailVerified) ...[
                          const SizedBox(height: 20),
                          _buildPasswordField(
                            controller: _newPasswordController,
                            label: 'New Password:',
                            hintText: 'Enter new password (min 6 characters)',
                            isVisible: _isPasswordVisible,
                            onToggle: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                          ),
                          const SizedBox(height: 20),
                          _buildPasswordField(
                            controller: _confirmPasswordController,
                            label: 'Confirm Password:',
                            hintText: 'Confirm your new password',
                            isVisible: _isConfirmPasswordVisible,
                            onToggle: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                          ),
                        ],
                        
                        const SizedBox(height: 20),
                        
                        // Description text
                        Text(
                          _emailVerified 
                              ? 'Your password will be updated immediately.'
                              : 'We\'ll verify your email and let you set a new password.',
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'Poppins-Regular',
                            color: Colors.black87,
                          ),
                        ),
                        
                        const SizedBox(height: 35),
                        
                        // Action Button
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFEDA5E),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Colors.black, width: 2),
                              ),
                              elevation: 5,
                            ),
                            onPressed: _isLoading 
                                ? null 
                                : (_emailVerified ? _resetPassword : _verifyEmail),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                    ),
                                  )
                                : Text(
                                    _emailVerified ? 'Reset Password' : 'Verify Email',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Lora-Regular',
                                    ),
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Back to Log In
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Back to Log In',
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'Poppins-Regular',
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFF8F8F8) : Colors.grey[300],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            enabled: enabled,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
              hintText: hintText,
              hintStyle: TextStyle(fontFamily: 'Poppins-Regular', color: Colors.grey[600]),
              border: InputBorder.none,
              prefixIcon: Icon(prefixIcon, color: Colors.black),
            ),
            style: const TextStyle(fontFamily: 'Poppins-Regular', fontSize: 16, color: Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required bool isVisible,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: TextField(
            controller: controller,
            obscureText: !isVisible,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
              hintText: hintText,
              hintStyle: TextStyle(fontFamily: 'Poppins-Regular', color: Colors.grey[600]),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.lock, color: Colors.black),
              suffixIcon: IconButton(
                icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off, color: Colors.black),
                onPressed: onToggle,
              ),
            ),
            style: const TextStyle(fontFamily: 'Poppins-Regular', fontSize: 16, color: Colors.black),
          ),
        ),
      ],
    );
  }
}







// SETTINGS SCREEN
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Account Policy',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            
            _buildSettingsItem(
              'Privacy Policy',
              Icons.privacy_tip,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                );
              },
            ),
            const SizedBox(height: 15),
            
            _buildSettingsItem(
              'Terms of use',
              Icons.description,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TermsOfUseScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem(String title, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                spreadRadius: 0.5,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.black, size: 24),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Lora-Regular',
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }
}

// LANGUAGES SCREEN
class LanguagesScreen extends StatefulWidget {
  const LanguagesScreen({super.key});

  @override
  State<LanguagesScreen> createState() => _LanguagesScreenState();
}

class _LanguagesScreenState extends State<LanguagesScreen> {
  String _selectedLanguage = 'English';
  final List<String> _languages = ['English', 'Filipino'];
  bool _isLoading = false;

  void _saveLanguage() async {
    setState(() {
      _isLoading = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isLoading = false;
    });

    _showSuccessSnackBar();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  void _showSuccessSnackBar() {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Language changed to $_selectedLanguage successfully!',
          style: TextStyle(
            fontFamily: 'Poppins-Regular',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Languages',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            Text(
              'Select your preferred language:',
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'Poppins-Regular',
              ),
            ),
            const SizedBox(height: 30),
            
            Expanded(
              child: ListView(
                children: _languages.map((language) {
                  return _buildLanguageOption(language, _selectedLanguage == language);
                }).toList(),
              ),
            ),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF59D),
                  foregroundColor: Colors.black,
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                    side: const BorderSide(color: Colors.black, width: 1),
                  ),
                ),
                onPressed: _isLoading ? null : _saveLanguage,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                        ),
                      )
                    : Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Lora-Regular',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(String language, bool isSelected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedLanguage = language;
          });
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.black,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                language,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Lora-Regular',
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: Colors.blue, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// HELP SCREEN
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Help & Support',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF59D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.help_outline,
                        size: 40,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    'SenyaMatika Help Center',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Lora-Regular',
              ),
            ),
            const SizedBox(height: 15),
            
            _buildFAQItem(
              'How can I track my learning progress?',
              'Visit the "Progress" section in your dashboard to see your overall progress, completed lessons, and exercises scores.'
            ),
            
            _buildFAQItem(
              'How do I contact support?',
              'You can reach our support team by emailing senyamatika.bulsu@gmail.com.'
            ),

            _buildFAQItem(
  'What does the avatar do when I\'m not using it?',
  'The avatar shows an idle animation. It\'s waiting for you to type or speak something to translate!'
),

_buildFAQItem(
  'How do I know which video to watch next?',
  'Videos are numbered in order. Complete the current video to unlock the next one. You can also see which videos are completed by the green checkmark.'
),

_buildFAQItem(
  'How do I change my password?',
  'Go to Profile → Edit Profile. Enter your new password in the "New Password" field and confirm it. Leave it blank if you don\'t want to change it.'
),

_buildFAQItem(
  'How does the Sign Language Avatar work?',
  'You can type any word or phrase, and the avatar will demonstrate the corresponding sign language. You can also use the microphone button to speak your text.'
),

_buildFAQItem(
  'How do I unlock the next topic?',
  'Topics are unlocked sequentially. You need to complete all lessons in the current topic (watch all videos and pass the exercises) to unlock the next topic.'
),
            
            const SizedBox(height: 30),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFA8D5E3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need More Help?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Our support team is here to help you with any questions or issues you may have.',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  _buildContactMethod('Email', 'senyamatika.bulsu@gmail.com', Icons.email),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            Center(
              child: Text(
                'App Version: 1.0.0',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Poppins-Regular',
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Lora-Regular',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            answer,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Poppins-Regular',
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactMethod(String method, String details, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                method,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Lora-Regular',
                ),
              ),
              Text(
                details,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Poppins-Regular',
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ABOUT SCREEN
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About SenyaMatika',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF59D),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.school,
                        size: 50,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    'SenyaMatika',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                  Text(
                    'Mathematics Learning App',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Poppins-Regular',
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            Text(
              'About Our App',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Lora-Regular',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'SenyaMatika is an innovative educational app designed to make learning mathematics fun and engaging for students of all ages. Our app combines lessons and progress tracking to help you undesrtand mathematical concepts.',
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'Poppins-Regular',
                height: 1.5,
              ),
            ),
            
            const SizedBox(height: 25),
            
            Text(
              'Key Features',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Lora-Regular',
              ),
            ),
            const SizedBox(height: 15),
            
            _buildFeatureItem('Interactive Lessons', 'Learn with engaging visual content and step-by-step explanations'),
            _buildFeatureItem('Progress Tracking', 'Monitor your learning journey with detailed progress reports'),
    
            _buildFeatureItem('Sign Language Support', 'Includes sign language dictionary for inclusive learning'),
            
            const SizedBox(height: 25),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5C6D6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow('Version', '1.0.0'),
                  _buildInfoRow('Last Updated', 'March 2026'),
                  _buildInfoRow('Developer', 'SenyaMatika Team'),
                  _buildInfoRow('Compatibility', 'Android 13.0+'),
                ],
              ),
            ),
            
            const SizedBox(height: 25),
        
            Center(
              child: Text(
                '© 2026 SenyaMatika. All rights reserved.',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Poppins-Regular',
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Lora-Regular',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Poppins-Regular',
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Lora-Regular',
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Poppins-Regular',
            ),
          ),
        ],
      ),
    );
  }
}

// PRIVACY POLICY SCREEN
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Privacy Policy',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              'Last Updated: March 2026',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Poppins-Regular',
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 20),
            
            _buildPolicySection(
              '1. Information We Collect',
              'We collect only the information necessary to improve your learning experience. This may include your name, email address, and usage data (such as topics completed or time spent in the app). We do not collect sensitive personal information without your consent.'
            ),
            
            _buildPolicySection(
              '2. How We Use Your Information',
              'We use the information we collect to provide and improve our educational content, track learning progress, and ensure the app functions properly. We do not sell or share your information with third parties for marketing purposes.'
            ),
            
            _buildPolicySection(
              '3. Data Security',
              'All personal data is stored securely and accessible only to authorized personnel. We take reasonable measures to protect your information from unauthorized access, alteration, or deletion.'
            ),
            
            _buildPolicySection(
              '4. Children\'s Privacy',
              'SenyaMatika is an educational app that may be used by children under 18. We collect only minimal information needed for learning purposes and do not share it with third parties. Parents or guardians can delete their child\'s account and all related data anytime by contacting us at senyamatikasupport.com.'
            ),
            
            _buildPolicySection(
              '5. Third-Party Services',
              'This app may use third-party services that collect data to help us understand how users interact with the app. These services follow their own privacy policies.'
            ),
            
            _buildPolicySection(
              '6. Your Rights',
              'You can view, update, or delete the application to also delete your personal information anytime through the app\'s settings.'
            ),
            
            _buildPolicySection(
              '9. Contact Us',
              'If you have any questions about this Privacy Policy:\n\n'
              'Email: senyamatika.bulsu@gmail.com\n'
            ),
            
            const SizedBox(height: 30),
            
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFA8D5E3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'By using SenyaMatika, you agree to the collection and use of information in accordance with this policy.',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We are committed to protecting your privacy and providing a safe learning environment.',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicySection(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Lora-Regular',
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Poppins-Regular',
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 15),
          const Divider(color: Colors.black54),
        ],
      ),
    );
  }
}

// TERMS OF USE SCREEN
class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Terms of Use',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lora-Regular',
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              'Last Updated: March 2026',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Poppins-Regular',
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Terms of Use',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Lora-Regular',
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'By using SenyaMatika, you agree to the User Responsibility. Please read them carefully.',
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'Poppins-Regular',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'User Responsibility',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Lora-Regular',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'You are responsible for maintaining the confidentiality of your account and password. You agree to accept responsibility for all activities that occur under your account.',
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'Poppins-Regular',
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



// ============ SIGN LANGUAGE AVATAR SCREEN (UPDATED) ============
class SignLanguageAvatarScreen extends StatefulWidget {
  const SignLanguageAvatarScreen({super.key});

  @override
  State<SignLanguageAvatarScreen> createState() => _SignLanguageAvatarScreenState();
}

class _SignLanguageAvatarScreenState extends State<SignLanguageAvatarScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _recognizedText = '';
  String _translationMessage = ''; // Store translation message
  List<String> _signSequence = []; // Store sequence of signs to play
  int _currentSignIndex = 0; // Current sign being played
  List<VideoPlayerController> _preloadedControllers = []; // All preloaded controllers
  VideoPlayerController? _currentController; // Currently playing controller
  VideoPlayerController? _idleController; // Idle state controller (paused at first frame)
  final TextEditingController _textController = TextEditingController();
  bool _speechAvailable = false;
  bool _isInitializing = true;
  Timer? _listeningTimer;
  
  // Avatar loading state
  bool _isAvatarLoading = false;
  bool _hasAvatarError = false;
  bool _hasUserInput = false; // Track if user has provided input
  bool _isTranslating = false; // Track if translating
  bool _isPlayingSequence = false; // Track if playing video sequence
  
  // ============ SIGN LANGUAGE ANIMATION SYSTEM ============
  
  // Method to handle text input and translate to sign language
  void _handleTextInput(String text) async {
    if (text.trim().isEmpty) return;
    
    // Prevent spam - ignore if already playing or translating
    if (_isPlayingSequence || _isTranslating || _isAvatarLoading) {
      debugPrint('⚠️ Already processing, ignoring duplicate request');
      return;
    }
    
    setState(() {
      _hasUserInput = true;
      _isAvatarLoading = true;
      _isTranslating = true;
      _translationMessage = '';
      _signSequence = [];
      _currentSignIndex = 0;
    });
    
    // Clean up old controllers
    _disposeAllControllers();
    
    // Translate to sign language sequence
    final sequence = SignLanguageService.translateToSignSequence(text);
    
    // PERFORMANCE FIX: Limit to max 8 signs to prevent lag/freeze on lower-end devices
    const int maxSigns = 8;
    final limitedSequence = sequence.length > maxSigns 
        ? sequence.sublist(0, maxSigns) 
        : sequence;
    
    if (mounted) {
      setState(() {
        _signSequence = limitedSequence;
        _isTranslating = false;
      });
      
      if (limitedSequence.isNotEmpty) {
        final truncatedMsg = sequence.length > maxSigns 
            ? ' (showing first $maxSigns of ${sequence.length})' 
            : '';
        _translationMessage = 'Loading ${limitedSequence.length} sign(s)...$truncatedMsg';
        setState(() {});
        
        // Preload ALL videos first
        await _preloadAllVideos();
        
        if (mounted && _preloadedControllers.isNotEmpty) {
          setState(() {
            _translationMessage = 'Playing ${limitedSequence.length} sign(s) for: "$text"$truncatedMsg';
          });
          _playSignSequence();
        }
      } else {
        setState(() {
          _translationMessage = 'No signs available for: "$text"';
          _isAvatarLoading = false;
        });
      }
    }
  }
  
  // Preload ALL videos before playing
  Future<void> _preloadAllVideos() async {
    debugPrint('📥 Preloading ${_signSequence.length} videos...');
    
    for (int i = 0; i < _signSequence.length; i++) {
      final videoPath = _signSequence[i];
      debugPrint('📥 Loading video ${i + 1}/${_signSequence.length}: $videoPath');
      
      try {
        final controller = VideoPlayerController.asset(videoPath);
        await controller.initialize();
        await controller.setPlaybackSpeed(1.5);
        _preloadedControllers.add(controller);
        debugPrint('✅ Loaded video ${i + 1}/${_signSequence.length}');
      } catch (e) {
        debugPrint('❌ Error loading video ${i + 1}: $e');
      }
    }
    
    debugPrint('✅ All videos preloaded: ${_preloadedControllers.length}/${_signSequence.length}');
  }
  
  // Play the sequence of preloaded videos
  void _playSignSequence() {
    if (_preloadedControllers.isEmpty) return;
    
    setState(() {
      _isPlayingSequence = true;
      _currentSignIndex = 0;
      _isAvatarLoading = false;
    });
    
    _playNextPreloadedVideo();
  }
  
  // Play the next preloaded video
  void _playNextPreloadedVideo() async {
    if (_currentSignIndex >= _preloadedControllers.length) {
      // Sequence complete
      setState(() {
        _isPlayingSequence = false;
        _translationMessage = 'Completed ${_signSequence.length} sign(s)';
      });
      return;
    }
    
    // Get the next controller
    final nextController = _preloadedControllers[_currentSignIndex];
    debugPrint('🎬 Playing preloaded sign ${_currentSignIndex + 1}/${_preloadedControllers.length}');
    
    // Remove listener from previous controller
    _currentController?.removeListener(_onVideoProgress);
    
    // Seek to start to ensure it's ready
    await nextController.seekTo(Duration.zero);
    
    // Switch to next controller
    _currentController = nextController;
    
    // Listen for video completion
    _currentController!.addListener(_onVideoProgress);
    
    // Update UI with the new controller
    if (mounted) {
      setState(() {});
    }
    
    // Start playing immediately
    await _currentController!.play();
  }
  
  // Monitor video progress
  void _onVideoProgress() {
    if (_currentController == null) return;
    
    if (_currentController!.value.position >= _currentController!.value.duration &&
        _currentController!.value.duration > Duration.zero) {
      // Video finished, remove listener and play next
      _currentController!.removeListener(_onVideoProgress);
      _currentSignIndex++;
      _playNextPreloadedVideo();
    }
  }
  
  // Dispose all controllers
  void _disposeAllControllers() {
    _currentController?.removeListener(_onVideoProgress);
    for (var controller in _preloadedControllers) {
      controller.dispose();
    }
    _preloadedControllers.clear();
    _currentController = null;
  }
  
  @override
  void dispose() {
    _disposeAllControllers();
    _idleController?.dispose();
    _speech.cancel();
    _cancelTimer();
    _textController.dispose();
    super.dispose();
  }
  // ============ END SIGN LANGUAGE ANIMATION SYSTEM ============

  @override
  void initState() {
    super.initState();
    _initializeIdleVideo();
    Future.delayed(const Duration(milliseconds: 500), () {
      _initSpeech();
    });
  }

  Future<void> _initializeIdleVideo() async {
    try {
      _idleController = VideoPlayerController.asset('assets/DataSet/Numbers/1s/sign-0.webm');
      await _idleController!.initialize();
      await _idleController!.setLooping(false);
      // Pause at first frame
      await _idleController!.seekTo(Duration.zero);
      setState(() {});
    } catch (e) {
      print('❌ Error initializing idle video: $e');
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          setState(() {
            _isListening = _speech.isListening;
          });
          
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
            _cancelTimer();
          }
        },
        onError: (errorNotification) {
          setState(() {
            _isListening = false;
          });
          _cancelTimer();
        },
        debugLogging: true,
      );
      
      setState(() {
        _isInitializing = false;
      });
      
    } catch (e) {
      setState(() {
        _speechAvailable = false;
        _isInitializing = false;
      });
    }
  }

  void _startListeningTimer() {
    _cancelTimer();
    
    _listeningTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (timer.tick == 1) {
        _showReminderSnackBar('Still listening...');
      } else if (timer.tick == 2) {
        _showReminderSnackBar('Still listening...');
      } else if (timer.tick == 5) {
        _showReminderSnackBar('Still listening...');
      } else if (timer.tick == 9) {
        _showReminderSnackBar('Speaking will auto-stop soon');
      }
    });
    
    Future.delayed(const Duration(minutes: 5), () {
      if (_isListening) {
        _showReminderSnackBar('Stopping speech recognition.');
        _stopListening();
      }
    });
  }

  void _cancelTimer() {
    if (_listeningTimer != null) {
      _listeningTimer!.cancel();
      _listeningTimer = null;
    }
  }

  Future<void> _stopListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
      });
      _cancelTimer();
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      setState(() {
        _isInitializing = true;
      });
      
      await _initSpeech();
      
      if (!_speechAvailable) {
        _showErrorSnackBar('Speech recognition is not available');
        return;
      }
    }
    
    if (_isListening) {
      await _stopListening();
    } else {
      if (!_speech.isAvailable) {
        bool initialized = await _speech.initialize();
        if (!initialized) {
          _showErrorSnackBar('Failed to initialize speech recognition');
          return;
        }
      }
      
      try {
        setState(() {
          _recognizedText = '';
          _textController.clear();
        });
        
        final options = stt.SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          onDevice: false,
          listenMode: stt.ListenMode.confirmation,
        );
        
        await _speech.listen(
          onResult: (result) {
            if (result.recognizedWords.isNotEmpty) {
              setState(() {
                _recognizedText = result.recognizedWords;
                _textController.text = _recognizedText;
              });
              
              if (result.confidence > 0.7) {
                _handleTextInput(result.recognizedWords);
              }
            }
          },
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 10),
          localeId: 'en-US',
          listenOptions: options,
        );
        
        setState(() {
          _isListening = true;
        });
        
        _startListeningTimer();
        
      } catch (e) {
        setState(() {
          _isListening = false;
        });
        _cancelTimer();
      }
    }
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _handleTextInput(text);
    } else {
      _showErrorSnackBar('Please enter or speak some text first');
    }
  }

  void _showReminderSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Sign Language Avatar',
          style: TextStyle(
            color: Colors.black,
            fontFamily: 'Lora-Regular',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // ============ AVATAR BACKGROUND (Full screen, close bust shot) ============
            Positioned.fill(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  
                  // TRANSLATION MESSAGE DISPLAY
                  if (_translationMessage.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _signSequence.isNotEmpty 
                            ? const Color(0xFFC8E6C9) // Green tint for success
                            : const Color(0xFFFFCDD2), // Red tint for not found
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                _signSequence.isNotEmpty ? Icons.play_circle : Icons.info,
                                color: _signSequence.isNotEmpty ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _translationMessage,
                                  style: TextStyle(
                                    fontFamily: 'Poppins-Regular',
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_isPlayingSequence && _signSequence.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                value: (_currentSignIndex + 1) / _signSequence.length,
                                backgroundColor: Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                              ),
                            ),
                        ],
                      ),
                    ),
                  
                  // ============ AVATAR DISPLAY (Larger, close bust shot) ============
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Avatar container - fills entire space
                        Positioned.fill(
                          child: _buildAvatar(),
                        ),
                        
                        // SPEECH INITIALIZING OVERLAY
                        if (_isInitializing)
                          Positioned.fill(
                            child: Container(
                              color: const Color.fromRGBO(0, 0, 0, 0.3),
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.yellow,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        
                        // LISTENING OVERLAY
                        if (_isListening)
                          Positioned.fill(
                            child: Container(
                              color: const Color.fromRGBO(0, 0, 0, 0.3),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withAlpha((0.8 * 255).round()),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.mic,
                                        size: 40,
                                        color: Colors.white,
                                      ),
                                    ),
                                    
                                    if (_recognizedText.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.all(10),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color.fromRGBO(0, 0, 0, 0.5),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '"$_recognizedText"',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontStyle: FontStyle.italic,
                                            fontFamily: 'Poppins-Regular',
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // ============ INPUT BOX OVERLAY (Bottom, over avatar's lower body) ============
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.7),
                      Colors.white,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 40), // Gradient fade area
                    
                    // TEXT INPUT FIELD WITH CONTROLS
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.black12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color.fromRGBO(0, 0, 0, 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                decoration: InputDecoration(
                                  hintText: _speechAvailable 
                                      ? 'Type or speak to translate...' 
                                      : 'Speech not available. Type here...',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(
                                    color: _speechAvailable ? Colors.grey : Colors.grey[400],
                                    fontFamily: 'Poppins-Regular',
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _recognizedText = value;
                                  });
                                },
                                onSubmitted: (value) {
                                  if (value.trim().isNotEmpty) {
                                    _sendText();
                                  }
                                },
                                style: TextStyle(fontFamily: 'Poppins-Regular'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            
                            // SEND BUTTON
                            if (_textController.text.trim().isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.send, color: Colors.blue),
                                onPressed: _sendText,
                                tooltip: 'Translate text to sign language',
                              ),
                            
                            // MICROPHONE BUTTON
                            IconButton(
                              icon: Icon(
                                _isListening ? Icons.mic_off : Icons.mic,
                                color: _isListening ? Colors.red : 
                                       _speechAvailable ? Colors.blue : Colors.grey,
                                size: 28,
                              ),
                              onPressed: _speechAvailable ? _toggleListening : null,
                              tooltip: _isListening 
                                ? 'Stop listening' 
                                : 'Start speaking',
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // INSTRUCTION TEXT
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 16, left: 16, right: 16),
                      child: Text(
                        _speechAvailable 
                            ? 'Tap the microphone and speak, or type text to translate'
                            : 'Speech recognition is not available. Please type your text.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _speechAvailable ? Colors.green : Colors.orange,
                          fontSize: 12,
                          fontFamily: 'Poppins-Regular',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: () {
        // Tap the avatar to replay animation if there's text
        final text = _textController.text.trim();
        if (text.isNotEmpty) {
          _handleTextInput(text);
        }
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFF9E6), // Light cream
              const Color(0xFFFFE5B4), // Peach
            ],
          ),
        ),
        child: Stack(
          children: [
            // ============ Static Video when no input (idle state) ============
            if (!_hasUserInput && _idleController != null && _idleController!.value.isInitialized)
              SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Transform.scale(
                      scale: 1.4, // Reduced scale to prevent going out of frame
                      child: Transform.translate(
                        offset: const Offset(0, 150), // Move down to show head to waist
                        child: SizedBox(
                          width: _idleController!.value.size.width,
                          height: _idleController!.value.size.height,
                          child: VideoPlayer(_idleController!),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            
            // ============ Video Player when playing sequence ============
            if (_hasUserInput && !_hasAvatarError && !_isAvatarLoading && _currentController != null && _currentController!.value.isInitialized)
              SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Transform.scale(
                      scale: 1.65, // Reduced scale to prevent going out of frame
                      child: Transform.translate(
                        offset: const Offset(0, 150), // Move down to show head to waist
                        child: SizedBox(
                          width: _currentController!.value.size.width,
                          height: _currentController!.value.size.height,
                          child: VideoPlayer(_currentController!),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            
            // Show message when no sign found
            if (_hasUserInput && !_isAvatarLoading && !_isTranslating && _signSequence.isEmpty)
              Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF59D).withOpacity(0.3),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 80,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Sign not found in dataset',
                          style: TextStyle(
                            fontFamily: 'Poppins-Regular',
                            fontSize: 18,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // LOADING OVERLAY (shows when loading new GIF)
            if (_hasUserInput && _isAvatarLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.white,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.yellow,
                    ),
                  ),
                ),
              ),
            
            // TRANSLATING OVERLAY
            if (_isTranslating)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFA8D5E3),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.yellow,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Translating...',
                          style: TextStyle(
                            fontFamily: 'Poppins-Regular',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            // ERROR OVERLAY
            if (_hasUserInput && _hasAvatarError && !_isAvatarLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.white,
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      size: 60,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackAvatar() {
    return Container(
      width: 500,
      height: 500,
      decoration: BoxDecoration(
        color: const Color(0xFFA8D5E3),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.person,
          size: 150,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ============ VIDEO DATA MANAGER ============
class VideoDataManager {
  // Master list ng lahat ng videos - ENSURE NA TUGMA ANG TITLES
  static final Map<String, List<Map<String, dynamic>>> _lessonVideos = {
    // NUMBER VALUES
    'Whole Numbers': [
      {
        'title': 'Count Up To 20',
        'videoUrl': 'assets/Videos/CountUpto20.mp4',
        'description': 'Learn how to count from 1 to 20',
      },
      {
        'title': 'Count Numbers Up to 50 (by 5s and 10s)',
        'videoUrl': 'assets/Videos/CountUpto50.mp4',
        'description': 'Learn to count numbers up to 50',
      },
      {
        'title': 'Count Numbers Up to 100 (by 5s, 10s and 20s)',
        'videoUrl': 'assets/Videos/CountUpto100.mp4',
        'description': 'Learn to count numbers up to 100',
      },
    ],
    'Comparison': [
      {
        'title': 'Compare Groups of Objects',
        'videoUrl': 'assets/Videos/ComparisonPt1.mp4',
        'description': 'Compare two groups/sets of objects',
      },
      {
        'title': 'Arrange Numbers in Order',
        'videoUrl': 'assets/Videos/ComparisonPt2.mp4',
        'description': 'Arrange objects/numbers from least to greatest',
      },
    ],

    // FUNDAMENTAL OPERATIONS
    'Addition': [
      {
        'title': 'Basic Addition Concepts',
        'videoUrl': 'assets/Videos/BasicConcept.mp4',
        'description': 'Illustrate addition as "putting together" or "combining" or "joining sets"',
      },
      {
        'title': 'Adding with Objects',
        'videoUrl': 'assets/Videos/Addobject.mp4',
        'description': 'Add quantities up to 20 using concrete objects',
      },
      {
        'title': 'Adding One to Two-Digit Numbers',
        'videoUrl': 'assets/Videos/Add1to2.mp4',
        'description': 'Add two one to two-digit numbers',
      },
      {
        'title': 'Properties of Addition',
        'videoUrl': 'assets/Videos/AdditionProperty.mp4',
        'description': 'Illustrate commutative, associative, and identity properties in addition',
      },
      {
        'title': 'Adding Larger Numbers',
        'videoUrl': 'assets/Videos/AddLarge.mp4',
        'description': 'Add up to 4-digit numbers with sums up to 1000',
      },
    ],
    'Subtraction': [
      {
        'title': 'Understanding Subtraction',
        'videoUrl': 'assets/Videos/UnderstandSubtract.mp4',
        'description': 'Recognize minus (-) sign that indicates the act of subtracting whole numbers',
      },
      {
        'title': 'Subtracting with Objects',
        'videoUrl': 'assets/Videos/SubtractObject.mp4',
        'description': 'Subtract quantities up to 20 using concrete objects',
      },
      {
        'title': 'Subtracting One to Two-Digit Numbers',
        'videoUrl': 'assets/Videos/Subtract1to2.mp4',
        'description': 'Subtract two one to two-digit numbers',
      },
      {
        'title': 'Subtracting Larger Numbers',
        'videoUrl': 'assets/Videos/SubtractLarge.mp4',
        'description': 'Subtract up to 4-digit numbers with minuends up to 1000',
      },
    ],
    'Multiplication': [
      {
        'title': 'Understanding Multiplication',
        'videoUrl': 'assets/Videos/UnderstandMulti.mp4',
        'description': 'Illustrate multiplication as repeated addition',
      },
      {
        'title': 'Representing Multiplication',
        'videoUrl': 'assets/Videos/RepresentMulti.mp4',
        'description': 'Represent multiplication of numbers',
      },
      {
        'title': 'Multiplying Numbers',
        'videoUrl': 'assets/Videos/MultiNumbers.mp4',
        'description': 'Multiply two one to two-digit numbers',
      },
      {
        'title': 'Properties of Multiplication',
        'videoUrl': 'assets/Videos/MultiProperty.mp4',
        'description': 'Illustrate the properties of multiplication',
      },
    ],
    'Division': [
      {
        'title': 'Understanding Division',
        'videoUrl': 'assets/Videos/Division.mp4',
        'description': 'Represents division as equal sharing',
      },
      {
        'title': 'Division as Repeated Subtraction',
        'videoUrl': 'assets/Videos/DivisionRepeated.mp4',
        'description': 'Illustrate division as repeated subtraction',
      },
      {
        'title': 'Dividing Numbers',
        'videoUrl': 'assets/Videos/DividingNumbers.mp4',
        'description': 'Divide two one to two-digit numbers',
      },
    ],

    // FRACTION
    'Fraction': [
      {
        'title': 'Recognizing Fractions',
        'videoUrl': 'assets/Videos/FractionsRecognizing.mp4',
        'description': 'Recognize and identify ¼, ½, ¾ of a whole object',
      },
      {
        'title': 'Describing Fractions',
        'videoUrl': 'assets/Videos/FractionsDescribing.mp4',
        'description': 'Describe a whole and ¼, ½ and ¾ of a whole',
      },
      {
        'title': 'Reading Fractions',
        'videoUrl': 'assets/Videos/FractionsReading.mp4',
        'description': 'Read fractions correctly',
      },
      {
        'title': 'Comparing Fractions',
        'videoUrl': 'assets/Videos/FractionsComparing.mp4',
        'description': 'Compare fractions using relation symbols (<, >, =)',
      },
      {
        'title': 'Ordering Fractions',
        'videoUrl': 'assets/Videos/FractionsOrdering.mp4',
        'description': 'Arrange fractions in increasing and decreasing order',
      },
    ],

    // DECIMAL NUMBERS
    'Decimal Numbers': [
      {
        'title': 'Decimal to Fraction Conversion',
        'videoUrl': 'assets/Videos/DecimalstoFraction.mp4',
        'description': 'Convert 0.125, 0.5, 0.75 to fractional form',
      },
      {
        'title': 'Place Value in Decimals',
        'videoUrl': 'assets/Videos/DecimalPlaceValue.mp4',
        'description': 'Identify the place value of every digit in decimal numbers',
      },
    ],

    // PERCENTAGE
    'Percentage': [
      {
        'title': 'Describing Percentage',
        'videoUrl': 'assets/Videos/PercentageDescribing.mp4',
        'description': 'Describe percentage as "parts per hundred"',
      },
      {
        'title': 'Converting Fractions to Percentages',
        'videoUrl': 'assets/Videos/Convertingfractionspercentage.mp4',
        'description': 'Convert 1/4 (25%) to percentage',
      },
      {
        'title': 'Converting Percentages to Fractions',
        'videoUrl': 'assets/Videos/Percentagestofractions.mp4',
        'description': 'Convert 25% to fraction form (1/4)',
      },
    ],

    // ALGEBRA
    'Algebra': [
      {
        'title': 'Missing Values in Addition',
        'videoUrl': 'assets/Videos/AlgebAdd.mp4',
        'description': 'Find the missing value to complete addition sentences',
      },
      {
        'title': 'Missing Values in Subtraction',
        'videoUrl': 'assets/Videos/AlgebSub.mp4',
        'description': 'Find the missing value to complete subtraction sentences',
      },
      {
        'title': 'Missing Values in Multiplication',
        'videoUrl': 'assets/Videos/AlgebMulti.mp4',
        'description': 'Find the missing value to complete multiplication sentences',
      },
      {
        'title': 'Missing Values in Division',
        'videoUrl': 'assets/Videos/AlgebDiv.mp4',
        'description': 'Find the missing value to complete division sentences',
      },
    ],
  };

  static int getVideoCount(String lessonName) {
    return _lessonVideos[lessonName]?.length ?? 1;
  }

  static List<Map<String, dynamic>> getVideos(String lessonName) {
    return _lessonVideos[lessonName] ?? [];
  }

  static Map<String, dynamic>? getVideo(String lessonName, int index) {
    final videos = _lessonVideos[lessonName];
    if (videos != null && index < videos.length) {
      return videos[index];
    }
    return null;
  }

  static int getTotalVideos() {
    int total = 0;
    _lessonVideos.forEach((key, value) {
      total += value.length;
    });
    return total;
  }

  static bool hasVideo(String lessonName) {
    return _lessonVideos.containsKey(lessonName);
  }
}

// ============ UPDATED PROGRESS MANAGER ============
class ProgressManager {
  static final ProgressManager _instance = ProgressManager._internal();
  factory ProgressManager() => _instance;
  ProgressManager._internal();

  /// Slots counted toward "X/Y exercises" on the progress page. Each lesson has
  /// one comprehensive exercise; every attempt (static + AI retakes) is stored
  /// as a separate row, so the numerator is capped to this value.
  static const int kExerciseSlotsPerLesson = 1;

  Map<String, Map<String, dynamic>> _progressData = {};
  String? _currentUserId;
  bool _isInitialized = false;
  
  final _unlockController = StreamController<String>.broadcast();
  Stream<String> get unlockStream => _unlockController.stream;

  void setCurrentUser(String? userId) {
    if (_currentUserId != userId) {
      if (_currentUserId != null && _isInitialized) {
        _saveProgressToStorage();
      }
      _currentUserId = userId;
      _isInitialized = false;
      _progressData = {};
      if (userId != null) {
        _loadProgressFromStorage();
      }
    }
  }

  Future<void> _loadProgressFromStorage() async {
    if (_currentUserId == null) return;
    
    try {
      final box = Hive.box('settings');
      final savedData = box.get('progress_$_currentUserId');
      
      if (savedData != null) {
        _progressData = Map<String, Map<String, dynamic>>.from(
          (savedData as Map).map((key, value) => 
            MapEntry(key.toString(), Map<String, dynamic>.from(value as Map))
          )
        );
      } else {
        _initializeEmptyProgress();
      }
      _isInitialized = true;
    } catch (e) {
      _initializeEmptyProgress();
      _isInitialized = true;
    }
  }

  Future<void> _saveProgressToStorage() async {
    if (_currentUserId == null) return;
    
    try {
      final box = Hive.box('settings');
      await box.put('progress_$_currentUserId', _progressData);
    } catch (e) {
      print('Error saving progress: $e');
    }
  }

  void _initializeEmptyProgress() {
    _progressData = {
      'video_lessons': {},
      'exercises': {},
      'subtopic_completion': {},
      'lesson_completion': {},
      'topic_completion': {},
      'lesson_exercise_insights': <String, Map<String, dynamic>>{},
      'topic_unlock': {
        'Number Values': {'unlocked': true}
      },
      'overall_stats': {
        'total_videos_watched': 0,
        'total_exercises_completed': 0,
        'total_score': 0,
        'average_score': 0.0,
        'total_questions_answered': 0,
        'correct_answers': 0,
        'progress_percentage': 0,
      }
    };
  }

  void initialize() {
    if (_progressData.isEmpty) {
      if (_currentUserId != null && !_isInitialized) {
        _loadProgressFromStorage();
      } else {
        _initializeEmptyProgress();
      }
    }
  }

  // ============ VIDEO PROGRESS METHODS ============
  void markVideoCompleted(String lessonName, String language, int subLessonIndex, String videoTitle) {
    initialize();
    
    final key = '$lessonName|$language|$subLessonIndex|$videoTitle';
    
    if (!_progressData['video_lessons']!.containsKey(key)) {
      final now = DateTime.now();
      
      _progressData['video_lessons']![key] = {
        'lesson_name': lessonName,
        'language': language,
        'sub_lesson_index': subLessonIndex,
        'video_title': videoTitle,
        'completed_at': now.toIso8601String(),
        'status': 'completed',
      };
      
      _progressData['overall_stats']!['total_videos_watched'] = 
          (_progressData['overall_stats']!['total_videos_watched'] as int) + 1;
    }
    
    _updateProgressPercentage();
    _saveProgressToStorage();
  }

  // ============ SUBTOPIC COMPLETION METHODS ============
  void markSubtopicCompleted(String lessonName, String subtopic) {
    initialize();
    
    if (!_progressData.containsKey('subtopic_completion')) {
      _progressData['subtopic_completion'] = {};
    }
    
    final key = '$lessonName|$subtopic';
    
    if (!_progressData['subtopic_completion']!.containsKey(key)) {
      final now = DateTime.now();
      
      _progressData['subtopic_completion']![key] = {
        'lesson_name': lessonName,
        'subtopic': subtopic,
        'completed_at': now.toIso8601String(),
        'status': 'completed',
        'type': 'video'
      };
      
      // Sync progress to backend
      _syncProgressToBackend(lessonName, subtopic);
    }
    
    _saveProgressToStorage();
  }
  
  // ============ BACKEND SYNC METHOD ============
  Future<void> _syncProgressToBackend(String lessonName, String subtopic) async {
    try {
      final studentId = ApiService.getStudentId();
      if (studentId == null) {
        debugPrint('⚠️ No student ID found, skipping backend sync');
        return;
      }
      
      // Find the lesson ID from TopicsData
      final lesson = TopicsData.getLessonByTitle(lessonName);
      if (lesson == null) {
        debugPrint('⚠️ Lesson not found: $lessonName');
        return;
      }
      
      // Find subtopic index (used as subtopic ID)
      final subtopicIndex = lesson.subtopics.indexOf(subtopic);
      if (subtopicIndex == -1) {
        debugPrint('⚠️ Subtopic not found: $subtopic in $lessonName');
        return;
      }
      
      final subtopicId = 'subtopic_${lesson.id}_${subtopicIndex + 1}';
      
      // Upload to backend (non-blocking)
      DataSyncService.uploadProgress(
        studentId: studentId,
        lessonId: lesson.id,
        subtopicId: subtopicId,
        completed: true,
      ).then((result) {
        if (result['success']) {
          debugPrint('✅ Progress synced to backend: $lessonName - $subtopic');
        } else {
          debugPrint('⚠️ Failed to sync progress: ${result['message']}');
        }
      }).catchError((error) {
        debugPrint('❌ Error syncing progress: $error');
      });
    } catch (e) {
      debugPrint('❌ Exception in _syncProgressToBackend: $e');
    }
  }

  bool isSubtopicCompleted(String lessonName, String subtopic) {
    initialize();
    
    if (!_progressData.containsKey('subtopic_completion')) {
      return false;
    }
    
    final key = '$lessonName|$subtopic';
    return _progressData['subtopic_completion']!.containsKey(key);
  }

  List<String> getCompletedSubtopicsForLesson(String lessonName) {
    initialize();
    
    if (!_progressData.containsKey('subtopic_completion')) {
      return [];
    }
    
    return _progressData['subtopic_completion']!.entries
        .where((entry) => entry.value['lesson_name'] == lessonName)
        .map((entry) => entry.value['subtopic'] as String)
        .toList();
  }

  // ============ LESSON COMPLETION METHODS ============
  void markLessonCompleted(String lessonName) {
    initialize();
    
    if (!_progressData.containsKey('lesson_completion')) {
      _progressData['lesson_completion'] = {};
    }
    
    final key = lessonName;
    
    if (!_progressData['lesson_completion']!.containsKey(key)) {
      final now = DateTime.now();
      
      _progressData['lesson_completion']![key] = {
        'lesson_name': lessonName,
        'completed_at': now.toIso8601String(),
        'status': 'completed',
      };
    }
    
    _saveProgressToStorage();
  }

  bool isLessonCompleted(String lessonName) {
    initialize();
    
    if (!_progressData.containsKey('lesson_completion')) {
      return false;
    }
    
    return _progressData['lesson_completion']!.containsKey(lessonName);
  }

  bool isLessonFullyCompleted(String lessonName) {
    initialize();
    
    final videos = VideoDataManager.getVideos(lessonName);
    if (videos.isEmpty) return false;
    
    int completedCount = 0;
    for (var video in videos) {
      if (isSubtopicCompleted(lessonName, video['title'])) {
        completedCount++;
      }
    }
    
    return completedCount == videos.length;
  }

  // ============ LESSON UNLOCK METHODS ============
  bool isLessonUnlocked(String lessonName) {
    initialize();
    
    // Number Values lessons
    if (lessonName == 'Whole Numbers') return true;
    if (lessonName == 'Comparison') {
      return isLessonFullyCompleted('Whole Numbers');
    }
    
    // Fundamental Operations lessons
    if (lessonName == 'Addition') {
      return isTopicUnlocked('Fundamental Operations');
    }
    if (lessonName == 'Subtraction') {
      return isLessonFullyCompleted('Addition');
    }
    if (lessonName == 'Multiplication') {
      return isLessonFullyCompleted('Subtraction');
    }
    if (lessonName == 'Division') {
      return isLessonFullyCompleted('Multiplication');
    }
    
    // Other topics - first lesson is unlocked if topic is unlocked
    if (lessonName == 'Fraction' || 
        lessonName == 'Decimal Numbers' || 
        lessonName == 'Percentage' || 
        lessonName == 'Algebra') {
      return isTopicUnlocked(lessonName);
    }
    
    return false;
  }

  // ============ LESSON PROGRESS METHODS ============
  Map<String, dynamic> getLessonProgress(String lessonName) {
    final videosCompleted = getCompletedVideosForLesson(lessonName);
    final exercisesCompleted = getCompletedExercisesForLesson(lessonName);
    final completedSubtopics = getCompletedSubtopicsForLesson(lessonName);
    final isUnlocked = isLessonUnlocked(lessonName);
    final isCompleted = isLessonCompleted(lessonName);
    
    final videoCount = VideoDataManager.getVideoCount(lessonName);
    final exerciseCount = kExerciseSlotsPerLesson;
    final subtopicCount = TopicsData.getSubtopicCountForLesson(lessonName);
    
    final lessonExercises = getExerciseScoresByLesson(lessonName);
    final averageScore = lessonExercises.isNotEmpty
        ? lessonExercises.fold(0.0, (sum, ex) => sum + (ex['percentage'] as double)) / lessonExercises.length
        : 0.0;
    
    double videoProgress = videoCount > 0 ? (videosCompleted / videoCount * 40) : 0;
    double exerciseProgress = exerciseCount > 0 ? (exercisesCompleted / exerciseCount * 30) : 0;
    double subtopicProgress = subtopicCount > 0 ? (completedSubtopics.length / subtopicCount * 30) : 0;
    
    double totalProgress = videoProgress + exerciseProgress + subtopicProgress;
    totalProgress = totalProgress > 100 ? 100 : totalProgress;
    
    return {
      'lesson_name': lessonName,
      'videos_completed': videosCompleted,
      'exercises_completed': exercisesCompleted,
      'completed_subtopics': completedSubtopics,
      'videoCount': videoCount,
      'exerciseCount': exerciseCount,
      'subtopicCount': subtopicCount,
      'average_score': averageScore,
      'total_attempts': lessonExercises.length,
      'best_score': lessonExercises.isNotEmpty
          ? lessonExercises.map((e) => e['percentage'] as double).reduce((a, b) => a > b ? a : b)
          : 0.0,
      'progress': totalProgress,
      'isUnlocked': isUnlocked,
      'isCompleted': isCompleted,
    };
  }

  // ============ VIDEO COUNT METHODS ============
  int getCompletedVideosForLesson(String lessonName) {
    initialize();
    return _progressData['video_lessons']!.values.where((video) {
      return video['lesson_name'] == lessonName;
    }).length;
  }

  int getCompletedVideosCount() {
    initialize();
    return _progressData['overall_stats']!['total_videos_watched'] as int;
  }

  // ============ EXERCISE METHODS ============
  void recordExerciseScore(String lessonName, String language, int subLessonIndex, 
                          String exerciseType, int score, int totalQuestions, 
                          int correctAnswers, double percentage) {
    initialize();
    
    final key = '$lessonName|$language|$subLessonIndex|$exerciseType|${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    
    _progressData['exercises']![key] = {
      'lesson_name': lessonName,
      'language': language,
      'sub_lesson_index': subLessonIndex,
      'exercise_type': exerciseType,
      'score': score,
      'total_questions': totalQuestions,
      'correct_answers': correctAnswers,
      'percentage': percentage,
      'completed_at': now.toIso8601String(),
      'passed': percentage >= 70,
    };
    
    _progressData['overall_stats']!['total_exercises_completed'] = 
        (_progressData['overall_stats']!['total_exercises_completed'] as int) + 1;
    _progressData['overall_stats']!['total_score'] = 
        (_progressData['overall_stats']!['total_score'] as int) + score;
    _progressData['overall_stats']!['total_questions_answered'] = 
        (_progressData['overall_stats']!['total_questions_answered'] as int) + totalQuestions;
    _progressData['overall_stats']!['correct_answers'] = 
        (_progressData['overall_stats']!['correct_answers'] as int) + correctAnswers;
    
    final totalExercises = _progressData['overall_stats']!['total_exercises_completed'] as int;
    final totalScore = _progressData['overall_stats']!['total_score'] as int;
    _progressData['overall_stats']!['average_score'] = 
        totalExercises > 0 ? (totalScore / totalExercises).toDouble() : 0.0;
    
    _updateProgressPercentage();
    _saveProgressToStorage();
    
    // Sync assessment score to backend
    _syncAssessmentToBackend(lessonName, score, totalQuestions);
  }
  
  // ============ BACKEND ASSESSMENT SYNC METHOD ============
  Future<void> _syncAssessmentToBackend(String lessonName, int score, int totalQuestions) async {
    try {
      final studentId = ApiService.getStudentId();
      if (studentId == null) {
        debugPrint('⚠️ No student ID found, skipping assessment sync');
        return;
      }
      
      // Find the lesson ID from TopicsData
      final lesson = TopicsData.getLessonByTitle(lessonName);
      if (lesson == null) {
        debugPrint('⚠️ Lesson not found for assessment: $lessonName');
        return;
      }
      
      // Create assessment ID based on lesson
      final assessmentId = 'assessment_${lesson.id}';
      
      // Upload to backend (non-blocking)
      DataSyncService.uploadAssessmentScore(
        studentId: studentId,
        assessmentId: assessmentId,
        score: score,
        maxScore: totalQuestions,
      ).then((result) {
        if (result['success']) {
          debugPrint('✅ Assessment score synced to backend: $lessonName - $score/$totalQuestions');
        } else {
          debugPrint('⚠️ Failed to sync assessment: ${result['message']}');
        }
      }).catchError((error) {
        debugPrint('❌ Error syncing assessment: $error');
      });
    } catch (e) {
      debugPrint('❌ Exception in _syncAssessmentToBackend: $e');
    }
  }

  List<Map<String, dynamic>> getExerciseScoresByLesson(String lessonName) {
    initialize();
    
    final exercises = _progressData['exercises']!.values.where((exercise) {
      return exercise['lesson_name'] == lessonName;
    }).toList();
    
    exercises.sort((a, b) => b['completed_at'].compareTo(a['completed_at']));
    
    return exercises.cast<Map<String, dynamic>>();
  }

  void _ensureLessonExerciseInsightsBucket() {
    initialize();
    if (!_progressData.containsKey('lesson_exercise_insights')) {
      _progressData['lesson_exercise_insights'] =
          <String, Map<String, dynamic>>{};
    }
  }

  /// Stores last AI exercise recap for My Progress lesson card "Insights".
  void saveLessonExerciseInsights(
    List<String> lessonNames, {
    required String summary,
    required List<String> recommendedSubtopics,
  }) {
    _ensureLessonExerciseInsightsBucket();
    final now = DateTime.now().toIso8601String();
    final unique = lessonNames
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toSet();
    for (final name in unique) {
      _progressData['lesson_exercise_insights']![name] = {
        'summary': summary,
        'recommended_subtopics': List<String>.from(recommendedSubtopics),
        'saved_at': now,
      };
    }
    _saveProgressToStorage();
  }

  /// Latest saved recap for [lessonName], or null if none / empty.
  Map<String, dynamic>? getLessonExerciseInsights(String lessonName) {
    _ensureLessonExerciseInsightsBucket();
    final raw = _progressData['lesson_exercise_insights']![lessonName];
    if (raw == null || raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final s = map['summary']?.toString().trim() ?? '';
    final topicsRaw = map['recommended_subtopics'];
    final topics = <String>[];
    if (topicsRaw is List) {
      for (final e in topicsRaw) {
        if (e != null) topics.add(e.toString());
      }
    }
    if (s.isEmpty && topics.isEmpty) return null;
    return {
      ...map,
      'summary': s,
      'recommended_subtopics': topics,
    };
  }

  int getCompletedExercisesForLesson(String lessonName) {
    initialize();
    final raw = _progressData['exercises']!.values.where((exercise) {
      return exercise['lesson_name'] == lessonName;
    }).length;
    return min(raw, kExerciseSlotsPerLesson);
  }

  /// Returns [true] if at least one recorded attempt for [lessonName] has
  /// a passing score (>= 70%). Both static and AI quiz sessions are included.
  bool hasEverPassedExercise(String lessonName) {
    initialize();
    return _progressData['exercises']!.values.any((exercise) =>
        exercise['lesson_name'] == lessonName && exercise['passed'] == true);
  }

  int getCompletedExercisesCount() {
    initialize();
    return _progressData['overall_stats']!['total_exercises_completed'] as int;
  }

  // ============ TOPIC METHODS ============
  void markTopicCompleted(String topicName) {
    initialize();
    
    if (!_progressData.containsKey('topic_completion')) {
      _progressData['topic_completion'] = {};
    }
    
    final now = DateTime.now();
    _progressData['topic_completion']![topicName] = {
      'topic_name': topicName,
      'completed_at': now.toIso8601String(),
    };
    _saveProgressToStorage();
  }

  bool isTopicCompleted(String topicName) {
    initialize();
    
    if (!_progressData.containsKey('topic_completion')) {
      return false;
    }
    
    return _progressData['topic_completion']!.containsKey(topicName);
  }

  bool isTopicUnlocked(String topicName) {
    initialize();
    
    if (topicName == 'Number Values') return true;
    
    // Check specific topic unlock conditions
    if (topicName == 'Fundamental Operations') {
      // Check if both Whole Numbers and Comparison are fully completed
      return isLessonFullyCompleted('Whole Numbers') && 
             isLessonFullyCompleted('Comparison');
    }
    
    if (topicName == 'Fraction') {
      // Check if all Fundamental Operations lessons are fully completed
      return isLessonFullyCompleted('Addition') &&
             isLessonFullyCompleted('Subtraction') &&
             isLessonFullyCompleted('Multiplication') &&
             isLessonFullyCompleted('Division');
    }
    
    if (topicName == 'Decimal Numbers') {
      return isLessonFullyCompleted('Fraction');
    }
    
    if (topicName == 'Percentage') {
      return isLessonFullyCompleted('Decimal Numbers');
    }
    
    if (topicName == 'Algebra') {
      return isLessonFullyCompleted('Percentage');
    }
    
    return _progressData['topic_unlock']!.containsKey(topicName);
  }

  void unlockTopic(String topicName) {
    initialize();
    
    if (!_progressData.containsKey('topic_unlock')) {
      _progressData['topic_unlock'] = {};
    }
    
    _progressData['topic_unlock']![topicName] = {
      'topic_name': topicName,
      'unlocked_at': DateTime.now().toIso8601String(),
    };
    
    _unlockController.add(topicName);
    _saveProgressToStorage();
  }

  // ============ OVERALL STATS METHODS ============
  double getOverallProgressPercentage() {
    initialize();
    int progress = _progressData['overall_stats']!['progress_percentage'] as int;
    return progress > 100 ? 100.0 : progress.toDouble();
  }

  Map<String, dynamic> getOverallStats() {
    initialize();
    return Map<String, dynamic>.from(_progressData['overall_stats']!);
  }

  List<Map<String, dynamic>> getLessonVideos(String lessonName) {
    return VideoDataManager.getVideos(lessonName);
  }

  void clearAllProgress() {
    _initializeEmptyProgress();
    _saveProgressToStorage();
  }

  void _updateProgressPercentage() {
    final videosWatched = getCompletedVideosCount();
    final exercisesCompleted = getCompletedExercisesCount();
    
    final videoWeight = 0.4;
    final exerciseWeight = 0.6;
    
    final totalVideos = VideoDataManager.getTotalVideos();
    final totalExercises = 13;
    
    final videoProgress = totalVideos > 0 ? (videosWatched / totalVideos) : 0;
    final exerciseProgress = totalExercises > 0 ? (exercisesCompleted / totalExercises) : 0;
    
    double overallProgress = (videoProgress * videoWeight + exerciseProgress * exerciseWeight) * 100;
    
    if (overallProgress > 100) {
      overallProgress = 100;
    }
    
    _progressData['overall_stats']!['progress_percentage'] = overallProgress.toInt();
  }
}

final progressManager = ProgressManager();

// ============ TOPICS CLASSES ============
class Topic {
  final String id;
  final String title;
  final List<Lesson> lessons;
  bool isExpanded;

  Topic({
    required this.id,
    required this.title,
    required this.lessons,
    this.isExpanded = false,
  });
}

class Lesson {
  final String id;
  final String title;
  final String topicId;
  final List<String> subtopics;

  Lesson({
    required this.id,
    required this.title,
    required this.topicId,
    required this.subtopics,
  });
}

// ============================================================
// TOPICS DATA — COMPLETE FIXED VERSION
// Replace your existing TopicsData class with this entire block.
// Key fix: uses _cachedTopics so the list is only built ONCE.
// ============================================================

class TopicsData {
  // Lazy cache — built only on first call, never again.
  static List<Topic>? _cachedTopics;

  static List<Topic> getTopics() {
    _cachedTopics ??= _buildTopics();
    return _cachedTopics!;
  }

  static List<Topic> _buildTopics() {
    return [
      Topic(
        id: 'topic1',
        title: '1. Number Values',
        lessons: [
          Lesson(
            id: 'lesson1_1',
            title: 'Whole Numbers',
            topicId: 'topic1',
            subtopics: [
              'Count Up To 20',
              'Count Numbers Up to 50 (by 5s and 10s)',
              'Count Numbers Up to 100 (by 5s, 10s and 20s)',
            ],
          ),
          Lesson(
            id: 'lesson1_2',
            title: 'Comparison',
            topicId: 'topic1',
            subtopics: [
              'Compare Groups of Objects',
              'Arrange Numbers in Order',
            ],
          ),
        ],
      ),
      Topic(
        id: 'topic2',
        title: '2. Fundamental Operations',
        lessons: [
          Lesson(
            id: 'lesson2_1',
            title: 'Addition',
            topicId: 'topic2',
            subtopics: [
              'Basic Addition Concepts',
              'Adding with Objects',
              'Adding One to Two-Digit Numbers',
              'Properties of Addition',
              'Adding Larger Numbers',
            ],
          ),
          Lesson(
            id: 'lesson2_2',
            title: 'Subtraction',
            topicId: 'topic2',
            subtopics: [
              'Understanding Subtraction',
              'Subtracting with Objects',
              'Subtracting One to Two-Digit Numbers',
              'Subtracting Larger Numbers',
            ],
          ),
          Lesson(
            id: 'lesson2_3',
            title: 'Multiplication',
            topicId: 'topic2',
            subtopics: [
              'Understanding Multiplication',
              'Representing Multiplication',
              'Multiplying Numbers',
              'Properties of Multiplication',
            ],
          ),
          Lesson(
            id: 'lesson2_4',
            title: 'Division',
            topicId: 'topic2',
            subtopics: [
              'Understanding Division',
              'Division as Repeated Subtraction',
              'Dividing Numbers',
            ],
          ),
        ],
      ),
      Topic(
        id: 'topic3',
        title: '3. Fraction',
        lessons: [
          Lesson(
            id: 'lesson3_1',
            title: 'Fraction',
            topicId: 'topic3',
            subtopics: [
              'Recognizing Fractions',
              'Describing Fractions',
              'Reading Fractions',
              'Comparing Fractions',
              'Ordering Fractions',
            ],
          ),
        ],
      ),
      Topic(
        id: 'topic4',
        title: '4. Decimal Numbers',
        lessons: [
          Lesson(
            id: 'lesson4_1',
            title: 'Decimal Numbers',
            topicId: 'topic4',
            subtopics: [
              'Decimal to Fraction Conversion',
              'Place Value in Decimals',
            ],
          ),
        ],
      ),
      Topic(
        id: 'topic5',
        title: '5. Percentage',
        lessons: [
          Lesson(
            id: 'lesson5_1',
            title: 'Percentage',
            topicId: 'topic5',
            subtopics: [
              'Describing Percentage',
              'Converting Fractions to Percentages',
              'Converting Percentages to Fractions',
            ],
          ),
        ],
      ),
      Topic(
        id: 'topic6',
        title: '6. Algebra',
        lessons: [
          Lesson(
            id: 'lesson6_1',
            title: 'Algebra',
            topicId: 'topic6',
            subtopics: [
              'Missing Values in Addition',
              'Missing Values in Subtraction',
              'Missing Values in Multiplication',
              'Missing Values in Division',
            ],
          ),
        ],
      ),
    ];
  }

  static List<Lesson> getAllLessons() {
    return getTopics().expand((topic) => topic.lessons).toList();
  }

  static Lesson? getLessonById(String id) {
    try {
      return getAllLessons().firstWhere((lesson) => lesson.id == id);
    } catch (e) {
      return null;
    }
  }

  static String getLessonNameById(String id) {
    final lesson = getLessonById(id);
    return lesson?.title ?? id;
  }

  static String getTopicIdForLesson(String lessonId) {
    final lesson = getLessonById(lessonId);
    return lesson?.topicId ?? '';
  }

  static List<String> getSubtopicsForLesson(String lessonId) {
    final lesson = getLessonById(lessonId);
    return lesson?.subtopics ?? [];
  }

  static Lesson? getLessonByTitle(String title) {
    try {
      return getAllLessons().firstWhere((lesson) => lesson.title == title);
    } catch (e) {
      return null;
    }
  }

  static List<String> getSubtopicsByLessonTitle(String title) {
    final lesson = getLessonByTitle(title);
    return lesson?.subtopics ?? [];
  }

  static List<Lesson> getLessonsByTopicTitle(String topicTitle) {
    try {
      final topic = getTopics().firstWhere((t) => t.title == topicTitle);
      return topic.lessons;
    } catch (e) {
      return [];
    }
  }

  static int getTotalSubtopics() {
    int total = 0;
    for (var topic in getTopics()) {
      for (var lesson in topic.lessons) {
        total += lesson.subtopics.length;
      }
    }
    return total;
  }

  static int getSubtopicCountForLesson(String lessonTitle) {
    final lesson = getLessonByTitle(lessonTitle);
    return lesson?.subtopics.length ?? 0;
  }

  static void printAllLessons() {
    print('=== ALL LESSONS AND SUBTOPICS ===');
    for (var topic in getTopics()) {
      print('\n${topic.title}:');
      for (var lesson in topic.lessons) {
        print('  ${lesson.title} (${lesson.subtopics.length} subtopics):');
        for (var subtopic in lesson.subtopics) {
          print('    • $subtopic');
        }
      }
    }
  }
}

// ============ TOPICS SCREEN (Simple Unlock Animation) ============
class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> 
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  
  // Simple flag para sa unlocking topic
  String? _unlockingTopic;
  
  final Map<String, Map<String, dynamic>> _topicAnimations = {
    'Number Values': {
      'type': 'bounce',
      'amplitude': 12.0,
      'color': Color(0xFFA8D5E3),
      'image': 'assets/images/number values logo.png',
    },
    'Fundamental Operations': {
      'type': 'float',
      'amplitude': 8.0,
      'rotation': 0.1,
      'color': Color(0xFFF5C6D6),
      'image': 'assets/images/fundamental operations.png',
    },
    'Fraction': {
      'type': 'rotate',
      'rotation': 0.3,
      'color': Color(0xFFC4B1E1),
      'image': 'assets/images/fraction.png',
    },
    'Decimal Numbers': {
      'type': 'pulse',
      'scale': 0.2,
      'color': Color(0xFFFFD8A8),
      'image': 'assets/images/decimal numbers.png',
    },
    'Percentage': {
      'type': 'wave',
      'amplitude': 15.0,
      'frequency': 4.0,
      'color': Color(0xFFA8E3B5),
      'image': 'assets/images/percentage.png',
    },
    'Algebra': {
      'type': 'swing',
      'amplitude': 20.0,
      'rotation': 0.4,
      'color': Color(0xFFD8A8FF),
      'image': 'assets/images/whiteboard.png',
    },
  };

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    
    // Listen for unlock events
    progressManager.unlockStream.listen((topicName) {
      if (mounted) {
        _showSimpleUnlockNotification(topicName);
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  // SIMPLE UNLOCK NOTIFICATION - walang red screen
  void _showSimpleUnlockNotification(String topicName) {
    setState(() {
      _unlockingTopic = topicName;
    });
    
    // I-flash lang ng konti ang topic
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _unlockingTopic = null;
        });
      }
    });
    
    // Show snackbar notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🔓 $topicName is now unlocked!',
          style: TextStyle(
            fontFamily: 'Poppins-Regular',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Check if topic is unlocked
  bool _isTopicUnlocked(String topicName) {
    return progressManager.isTopicUnlocked(topicName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Topics',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _topicAnimations.keys.map((topic) {
              final config = _topicAnimations[topic]!;
              final isUnlocked = _isTopicUnlocked(topic);
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _buildTopicItem(
                  topic,
                  config['color'] as Color,
                  config['image'] as String,
                  config,
                  isUnlocked,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTopicItem(
    String topicName,
    Color boxColor,
    String imagePath,
    Map<String, dynamic> animationConfig,
    bool isUnlocked,
  ) {
    // Simple animation para sa bagong unlock
    bool isNewlyUnlocked = (_unlockingTopic == topicName);
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      transform: isNewlyUnlocked ? Matrix4.diagonal3Values(1.05, 1.05, 1.0) : Matrix4.identity(),
      child: GestureDetector(
        onTap: isUnlocked ? () {
          _navigateToTopic(topicName, context);
        } : null,
        child: Container(
          width: 330,
          height: 187,
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: isUnlocked ? boxColor : boxColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isUnlocked ? Colors.black : Colors.grey.shade400,
              width: 1,
            ),
            boxShadow: isNewlyUnlocked ? [
              BoxShadow(
                color: Colors.green.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    topicName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isUnlocked ? Colors.black : Colors.grey.shade600,
                    ),
                  ),
                  if (!isUnlocked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'LOCKED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: Opacity(
                    opacity: isUnlocked ? 1.0 : 0.5,
                    child: _buildAnimatedIcon(imagePath, animationConfig),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIcon(
    String imagePath,
    Map<String, dynamic> animationConfig,
  ) {
    final animationType = animationConfig['type'] as String;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final value = _animationController.value;
        
        switch (animationType) {
          case 'bounce':
            final amplitude = (animationConfig['amplitude'] as double?) ?? 12.0;
            final offset = sin(value * 2 * pi) * amplitude;
            return Transform.translate(offset: Offset(0, offset), child: child);
          case 'float':
            final amplitude = (animationConfig['amplitude'] as double?) ?? 8.0;
            final rotation = (animationConfig['rotation'] as double?) ?? 0.05;
            final offset = sin(value * 2 * pi) * amplitude;
            final angle = sin(value * 2 * pi) * rotation;
            return Transform.translate(
              offset: Offset(0, offset),
              child: Transform.rotate(angle: angle, child: child),
            );
          case 'rotate':
            final rotation = (animationConfig['rotation'] as double?) ?? 0.2;
            final angle = sin(value * 2 * pi) * rotation;
            return Transform.rotate(angle: angle, child: child);
          case 'pulse':
            final scaleAmount = (animationConfig['scale'] as double?) ?? 0.1;
            final scale = 1.0 + sin(value * 2 * pi) * scaleAmount;
            return Transform.scale(scale: scale, child: child);
          case 'wave':
            final amplitude = (animationConfig['amplitude'] as double?) ?? 15.0;
            final frequency = (animationConfig['frequency'] as double?) ?? 4.0;
            final offset = sin(value * frequency * pi) * amplitude;
            return Transform.translate(offset: Offset(0, offset), child: child);
          case 'swing':
            final amplitude = (animationConfig['amplitude'] as double?) ?? 20.0;
            final rotation = (animationConfig['rotation'] as double?) ?? 0.4;
            final offset = sin(value * 2 * pi) * (amplitude / 2);
            final angle = sin(value * 2 * pi) * rotation;
            return Transform.rotate(
              angle: angle,
              child: Transform.translate(offset: Offset(0, offset), child: child),
            );
          default:
            return child!;
        }
      },
      child: _buildLogoImage(imagePath),
    );
  }

  Widget _buildLogoImage(String imagePath) {
    return Image.asset(
      imagePath,
      height: 80,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return _buildFallbackIcon(imagePath);
      },
    );
  }

  Widget _buildFallbackIcon(String imagePath) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final value = _animationController.value;
        final scale = 1.0 + sin(value * 2 * pi) * 0.1;
        
        return Transform.scale(
          scale: scale,
          child: Icon(
            _getIconForTopic(imagePath),
            size: 80,
            color: Colors.black.withOpacity(0.7),
          ),
        );
      },
    );
  }

  IconData _getIconForTopic(String imagePath) {
    if (imagePath.contains('number values')) return Icons.numbers;
    if (imagePath.contains('fundamental operations')) return Icons.calculate;
    if (imagePath.contains('fraction')) return Icons.pie_chart;
    if (imagePath.contains('decimal numbers')) return Icons.money;
    if (imagePath.contains('percentage')) return Icons.percent;
    if (imagePath.contains('algebra')) return Icons.square_foot;
    return Icons.school;
  }

  void _navigateToTopic(String topicName, BuildContext context) {
    switch (topicName) {
      case 'Number Values':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const NumberValuesLessonsScreen()),
        ).then((_) => setState(() {}));
        break;
      case 'Fundamental Operations':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const FundamentalOperationsLessonsScreen()),
        ).then((_) => setState(() {}));
        break;
      case 'Fraction':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const FractionLessonsScreen()),
        ).then((_) => setState(() {}));
        break;
      case 'Decimal Numbers':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DecimalNumbersLessonsScreen()),
        ).then((_) => setState(() {}));
        break;
      case 'Percentage':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PercentageLessonsScreen()),
        ).then((_) => setState(() {}));
        break;
      case 'Algebra':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AlgebraLessonsScreen()),
        ).then((_) => setState(() {}));
        break;
    }
  }
}

// ============ UPDATED NUMBER VALUES VIDEO SCREEN - AUTO BACK ============
class NumberValuesVideoScreen extends StatefulWidget {
  final String lessonTitle;
  final String videoTitle;
  final String videoUrl;
  final String? learningObjective;

  const NumberValuesVideoScreen({
    super.key,
    required this.lessonTitle,
    required this.videoTitle,
    required this.videoUrl,
    this.learningObjective,
  });

  @override
  State<NumberValuesVideoScreen> createState() => _NumberValuesVideoScreenState();
}

class _NumberValuesVideoScreenState extends State<NumberValuesVideoScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _videoCompleted = false;
  bool _isCheckingCompletion = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset(widget.videoUrl);
      await _videoController.initialize();

      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
        _videoCompleted = false;
      });
      
      _videoController.setLooping(false);
      _videoController.play();
      
      _videoController.addListener(() {
        if (_videoController.value.position == _videoController.value.duration && 
            _videoController.value.isPlaying == false) {
          if (!_videoCompleted && !_isCheckingCompletion) {
            setState(() {
              _videoCompleted = true;
            });
            _markAsComplete();
          }
        }
      });
      
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _markAsComplete() async {
    if (_isCheckingCompletion) return;
    
    setState(() => _isCheckingCompletion = true);
    
    // Mark video as completed
    progressManager.markVideoCompleted(
      widget.lessonTitle, 
      'English', 
      0, 
      widget.videoTitle
    );
    
    // Mark subtopic as completed
    progressManager.markSubtopicCompleted(
      widget.lessonTitle,
      widget.videoTitle
    );
    
    // Small delay to ensure progress is updated
    await Future.delayed(const Duration(milliseconds: 300));
    
    setState(() => _isCheckingCompletion = false);
    
    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Video marked as complete!',
            style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    
    // Check if Number Values topic is now fully completed
    _checkNumberValuesCompletion();
    
    // AUTO BACK TO LESSONS AFTER SHORT DELAY
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      Navigator.pop(context); // Go back to lessons list
    }
  }

  void _checkNumberValuesCompletion() {
    bool wholeNumbersCompleted = progressManager.isLessonCompleted('Whole Numbers');
    bool comparisonCompleted = progressManager.isLessonCompleted('Comparison');
    
    if (wholeNumbersCompleted && comparisonCompleted) {
      progressManager.markTopicCompleted('Number Values');
      progressManager.unlockTopic('Fundamental Operations');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔓 Fundamental Operations is now unlocked!',
              style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _changePlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _videoController.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    _videoController.removeListener(() {});
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.lessonTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.videoTitle,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Lora-Regular'),
                  ),
                  const SizedBox(height: 10),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: _isVideoInitialized ? _videoController.value.aspectRatio : 16/9,
                          child: _hasError
                              ? _buildErrorWidget()
                              : _isVideoInitialized
                                  ? VideoPlayer(_videoController)
                                  : _buildLoadingWidget(),
                        ),
                        if (_isVideoInitialized && !_hasError) _buildVideoControls(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  
                  if (widget.learningObjective != null && widget.learningObjective!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.school, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Learning Objective:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                  fontFamily: 'Lora-Regular',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.learningObjective!,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Poppins-Regular',
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                  
                  if (!_videoCompleted && _isVideoInitialized && !_hasError)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 5,
                        ),
                        onPressed: _markAsComplete,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Mark as Complete',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Lora-Regular'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  if (_videoCompleted)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.check_circle, color: Colors.green, size: 30),
                          SizedBox(width: 10),
                          Text(
                            'Video Completed!',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green, fontFamily: 'Lora-Regular'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.yellow),
            SizedBox(height: 10),
            Text('Loading video...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            const Text('Video not available', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFF59D)),
              onPressed: _initializeVideo,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Speed:', style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Text('${_playbackSpeed}x', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, size: 16, color: Colors.white),
                onSelected: _changePlaybackSpeed,
                itemBuilder: (context) => _speedOptions.map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x Speed', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(_videoController.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _videoController.value.isPlaying ? _videoController.pause() : _videoController.play();
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position - const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              Text(_formatDuration(_videoController.value.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: VideoProgressIndicator(
                  _videoController,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: Colors.yellow, bufferedColor: Colors.grey, backgroundColor: Colors.white24),
                ),
              ),
              Text(_formatDuration(_videoController.value.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position + const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  _videoController.seekTo(Duration.zero);
                  _videoController.play();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

// ============ UPDATED NUMBER VALUES LESSONS SCREEN ============
class NumberValuesLessonsScreen extends StatefulWidget {
  const NumberValuesLessonsScreen({super.key});

  @override
  State<NumberValuesLessonsScreen> createState() => _NumberValuesLessonsScreenState();
}

class _NumberValuesLessonsScreenState extends State<NumberValuesLessonsScreen> {
  final Map<String, bool> _expandedLessons = {
    'whole_numbers': true,
    'comparison': false,
  };

  final List<Map<String, dynamic>> _lessons = [
    {
      'id': 'whole_numbers',
      'title': 'Whole Numbers',
      'description': 'Learn to count and identify numbers',
      'hasDropdown': true,
      'videos': [
        {
          'title': 'Count Up To 20',
          'videoUrl': 'assets/Videos/CountUpto20.mp4',
          'learningObjective': 'Learn to count from 1 to 20',
          'duration': '1:54',
        },
        {
          'title': 'Count Numbers Up to 50 (by 5s and 10s)',
          'videoUrl': 'assets/Videos/CountUpto50.mp4',
          'learningObjective': 'Learn to count numbers up to 50',
          'duration': '1:23',
        },
        {
          'title': 'Count Numbers Up to 100 (by 5s, 10s and 20s)',
          'videoUrl': 'assets/Videos/CountUpto100.mp4',
          'learningObjective': 'Learn to count numbers up to 100',
          'duration': '2:34', 
        },
      ],
      'color': const Color(0xFFA8D5E3),
      'icon': Icons.numbers,
    },
    
    {
      'id': 'comparison',
      'title': 'Comparison',
      'description': 'Learn to compare and arrange numbers',
      'hasDropdown': true,
      'videos': [
        {
          'title': 'Compare Groups of Objects',
          'videoUrl': 'assets/Videos/ComparisonPt1.mp4',
          'learningObjective': 'Compare two groups/sets of objects',
          'duration': '2:17',
        },
        {
          'title': 'Arrange Numbers in Order',
          'videoUrl': 'assets/Videos/ComparisonPt2.mp4',
          'learningObjective': 'Arrange objects/numbers from least to greatest',
          'duration': '1:25',
        },
      ],
      'color': const Color(0xFFF5C6D6),
      'icon': Icons.compare_arrows,
    },
  ];

  @override
  void initState() {
    super.initState();
    progressManager.unlockStream.listen((topicName) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  bool _isLessonUnlocked(String lessonTitle) {
    if (lessonTitle == 'Whole Numbers') return true;
    if (lessonTitle == 'Comparison') {
      return _isLessonFullyCompleted('Whole Numbers');
    }
    return false;
  }

  bool _isLessonFullyCompleted(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final videos = lesson['videos'] as List;
      
      if (videos.isEmpty) return false;
      
      int completedCount = 0;
      for (var video in videos) {
        if (progressManager.isSubtopicCompleted(lessonTitle, video['title'])) {
          completedCount++;
        }
      }
      
      return completedCount == videos.length;
    } catch (e) {
      return false;
    }
  }

  bool _isVideoUnlocked(String lessonTitle, int videoIndex) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final videos = lesson['videos'] as List;
      
      if (videoIndex == 0) {
        return _isLessonUnlocked(lessonTitle);
      }
      
      final previousVideo = videos[videoIndex - 1];
      return progressManager.isSubtopicCompleted(lessonTitle, previousVideo['title']);
    } catch (e) {
      return false;
    }
  }

  void _toggleLesson(String lessonId) {
    setState(() {
      _expandedLessons[lessonId] = !(_expandedLessons[lessonId] ?? false);
    });
  }

  void _navigateToVideo(String lessonTitle, String videoTitle, String videoUrl, 
      {String? learningObjective, bool isUnlocked = false}) {
    if (!isUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete the previous video first!',
            style: const TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NumberValuesVideoScreen(
          lessonTitle: lessonTitle,
          videoTitle: videoTitle,
          videoUrl: videoUrl,
          learningObjective: learningObjective,
        ),
      ),
    ).then((_) {
      setState(() {});
      _checkNumberValuesCompletion();
    });
  }

  void _navigateToComprehensiveExercise(String lessonTitle) {
    if (lessonTitle == 'Whole Numbers') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WholeNumbersExerciseScreen(
          lessonName: 'Whole Numbers',
          language: 'English',
        )),
      ).then((_) {
        setState(() {});
      });
    } else if (lessonTitle == 'Comparison') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ComparisonComprehensiveExerciseScreen(
          lessonName: 'Comparison',
          language: 'English',
        )),
      ).then((_) {
        setState(() {});
      });
    }
  }

  void _checkNumberValuesCompletion() {
    bool wholeNumbersCompleted = _isLessonFullyCompleted('Whole Numbers');
    bool comparisonCompleted = _isLessonFullyCompleted('Comparison');
    
    if (wholeNumbersCompleted && comparisonCompleted) {
      if (!progressManager.isTopicCompleted('Number Values')) {
        progressManager.markTopicCompleted('Number Values');
      }
      
      // Unlock Fundamentals Operations
      if (!progressManager.isTopicUnlocked('Fundamental Operations')) {
        progressManager.unlockTopic('Fundamental Operations');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔓 Fundamental Operations is now unlocked!',
              style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  double _getLessonProgress(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final videos = lesson['videos'] as List;
      
      if (videos.isEmpty) return 0;
      
      int completedCount = 0;
      for (var video in videos) {
        if (progressManager.isSubtopicCompleted(lessonTitle, video['title'])) {
          completedCount++;
        }
      }
      
      return completedCount / videos.length;
    } catch (e) {
      return 0;
    }
  }

  int _getCompletedCount(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final videos = lesson['videos'] as List;
      
      int completedCount = 0;
      for (var video in videos) {
        if (progressManager.isSubtopicCompleted(lessonTitle, video['title'])) {
          completedCount++;
        }
      }
      
      return completedCount;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Number Values',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFA8D5E3).withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA8D5E3), width: 2),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Number Values Lessons',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Complete all videos in each lesson to unlock the next lesson.',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            ..._lessons.map((lesson) {
              final isLessonUnlocked = _isLessonUnlocked(lesson['title'] as String);
              final isLessonCompleted = progressManager.isLessonCompleted(lesson['title'] as String);
              final isFullyCompleted = _isLessonFullyCompleted(lesson['title'] as String);
              
              return _buildDropdownLesson(lesson, isLessonUnlocked, isLessonCompleted, isFullyCompleted);
            }).toList(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownLesson(Map<String, dynamic> lesson, bool isLessonUnlocked, bool isLessonCompleted, bool isFullyCompleted) {
    final isExpanded = _expandedLessons[lesson['id'] as String] ?? false;
    final videos = lesson['videos'] as List;
    final lessonTitle = lesson['title'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? lesson['color'] as Color : Colors.grey.shade400),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLessonUnlocked ? () => _toggleLesson(lesson['id'] as String) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isLessonCompleted ? Colors.green.withOpacity(0.2) : (isLessonUnlocked ? lesson['color'] as Color : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: isLessonCompleted
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 30)
                          : Icon(
                              isLessonUnlocked ? lesson['icon'] as IconData : Icons.lock,
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lessonTitle,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${videos.length} subtopics',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Poppins-Regular',
                              color: isLessonUnlocked ? Colors.grey[600] : Colors.grey.shade500,
                            ),
                          ),
                          
                          if (lessonTitle == 'Comparison' && !isLessonUnlocked)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Complete all Whole Numbers videos first',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          if (isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Completed',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (isLessonUnlocked)
                      Row(
                        children: [
                          if (isFullyCompleted && !isLessonCompleted)
                            GestureDetector(
                              onTap: () => _navigateToComprehensiveExercise(lessonTitle),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.black),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.assignment, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Exercise',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey[400]!),
                            ),
                            child: Icon(
                              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded && isLessonUnlocked)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border(top: BorderSide(color: lesson['color'] as Color, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson['description'] as String,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  LinearProgressIndicator(
                    value: _getLessonProgress(lessonTitle),
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_getCompletedCount(lessonTitle)}/${videos.length} videos completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  
                  const SizedBox(height: 15),
                  
                  ...List.generate(videos.length, (index) {
                    final video = videos[index] as Map<String, dynamic>;
                    final isVideoUnlocked = _isVideoUnlocked(lessonTitle, index);
                    final isVideoCompleted = progressManager.isSubtopicCompleted(lessonTitle, video['title'] as String);
                    
                    return _buildVideoItem(
                      lessonTitle: lessonTitle,
                      videoTitle: video['title'] as String,
                      videoUrl: video['videoUrl'] as String,
                      duration: video['duration'] as String,
                      learningObjective: video['learningObjective'] as String?,
                      index: index,
                      isUnlocked: isVideoUnlocked,
                      isCompleted: isVideoCompleted,
                    );
                  }),
                  
                  if (isFullyCompleted && !isLessonCompleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => _navigateToComprehensiveExercise(lessonTitle),
                          child: const Text(
                            'Take Comprehensive Lesson Exercise',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoItem({
    required String lessonTitle,
    required String videoTitle,
    required String videoUrl,
    required String duration,
    String? learningObjective,
    required int index,
    required bool isUnlocked,
    required bool isCompleted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isUnlocked ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCompleted ? Colors.green : (isUnlocked ? Colors.grey[300]! : Colors.grey.shade300),
          width: isCompleted ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? () => _navigateToVideo(
            lessonTitle, 
            videoTitle, 
            videoUrl,
            learningObjective: learningObjective,
            isUnlocked: isUnlocked,
          ) : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green.withOpacity(0.2) : (isUnlocked ? (lessonTitle == 'Whole Numbers' ? const Color(0xFFA8D5E3).withOpacity(0.3) : const Color(0xFFF5C6D6).withOpacity(0.3)) : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted ? Colors.green : (isUnlocked ? (lessonTitle == 'Whole Numbers' ? const Color(0xFFA8D5E3) : const Color(0xFFF5C6D6)) : Colors.grey.shade400),
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, size: 16, color: Colors.green)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isUnlocked ? Colors.black : Colors.grey.shade600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            videoTitle,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 12, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                duration,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!isUnlocked && !isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.orange.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                      const SizedBox(width: 2),
                                      const Text(
                                        'Locked',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                      const SizedBox(width: 2),
                                      const Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFFFF59D) : Colors.grey.shade300),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted ? Colors.green.shade700 : (isUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : (isUnlocked ? Icons.play_arrow : Icons.lock),
                        color: isCompleted ? Colors.white : (isUnlocked ? Colors.black : Colors.grey.shade600),
                        size: 16,
                      ),
                    ),
                  ],
                ),
                
                if (learningObjective != null && learningObjective.isNotEmpty && isUnlocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 42),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        learningObjective,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Poppins-Regular',
                          color: Colors.blue.shade800,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin wrapper â€” exercise logic lives in the [exercise_feature.ExerciseScreen] module.
class WholeNumbersExerciseScreen extends StatelessWidget {
  final String lessonName;
  final String language;
  const WholeNumbersExerciseScreen(
      {super.key, required this.lessonName, required this.language});
  @override
  Widget build(BuildContext context) {
    final flags = aggregateProgressFlags(
      [lessonName],
      completedCount: progressManager.getCompletedExercisesForLesson,
      hasPassed: progressManager.hasEverPassedExercise,
    );
    final lesson = TopicsData.getLessonByTitle(lessonName);
    final topic = lesson != null
        ? TopicsData.getTopics().firstWhere(
            (t) => t.id == lesson.topicId,
            orElse: () => TopicsData.getTopics().first,
          )
        : null;
    return exercise_feature.ExerciseScreen(
      lessonName: lessonName,
      language: language,
      title: 'Whole Numbers Exercise',
      questions: WholeNumbersQuestions.all,
      showAiRemediation: true,
      autoStartRemediation: shouldAutoStartRemediation(
        hasAnyAttempt: flags.hasAnyAttempt,
        hasAnyPass: flags.hasAnyPass,
      ),
      lessonId: lesson?.id ?? lessonName,
      aiLessonContext: buildAiLessonContext(
        lessonTitle: lessonName,
        subtopics: lesson?.subtopics ?? [],
        topicId: lesson?.topicId,
        topicTitle: topic?.title,
      ),
      onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>
          progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),
      onExerciseInsightsSaved: (names, summary, topics) =>
          progressManager.saveLessonExerciseInsights(
            names,
            summary: summary,
            recommendedSubtopics: topics,
          ),
    );
  }
}

/// Thin wrapper â€” exercise logic lives in the [exercise_feature.ExerciseScreen] module.
class ComparisonComprehensiveExerciseScreen extends StatelessWidget {
  final String lessonName;
  final String language;
  const ComparisonComprehensiveExerciseScreen(
      {super.key, required this.lessonName, required this.language});
  @override
  Widget build(BuildContext context) {
    final flags = aggregateProgressFlags(
      [lessonName],
      completedCount: progressManager.getCompletedExercisesForLesson,
      hasPassed: progressManager.hasEverPassedExercise,
    );
    final lesson = TopicsData.getLessonByTitle(lessonName);
    final topic = lesson != null
        ? TopicsData.getTopics().firstWhere(
            (t) => t.id == lesson.topicId,
            orElse: () => TopicsData.getTopics().first,
          )
        : null;
    return exercise_feature.ExerciseScreen(
      lessonName: lessonName,
      language: language,
      title: 'Comparison Exercise',
      questions: ComparisonQuestions.all,
      showAiRemediation: true,
      autoStartRemediation: shouldAutoStartRemediation(
        hasAnyAttempt: flags.hasAnyAttempt,
        hasAnyPass: flags.hasAnyPass,
      ),
      lessonId: lesson?.id ?? lessonName,
      aiLessonContext: buildAiLessonContext(
        lessonTitle: lessonName,
        subtopics: lesson?.subtopics ?? [],
        topicId: lesson?.topicId,
        topicTitle: topic?.title,
      ),
      onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>
          progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),
      onExerciseInsightsSaved: (names, summary, topics) =>
          progressManager.saveLessonExerciseInsights(
            names,
            summary: summary,
            recommendedSubtopics: topics,
          ),
    );
  }
}

class VideoLessonScreen extends StatefulWidget {
  final String lessonName;
  final String language;
  final int subLessonIndex;
  final String? videoTitle; // Optional, will use default if not provided

  const VideoLessonScreen({
    super.key,
    required this.lessonName,
    required this.language,
    required this.subLessonIndex,
    this.videoTitle,
  });

  @override
  State<VideoLessonScreen> createState() => _VideoLessonScreenState();
}

class _VideoLessonScreenState extends State<VideoLessonScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _videoCompleted = false;
  bool _isCheckingCompletion = false;
  
  Map<String, dynamic>? _videoData;

  @override
  void initState() {
    super.initState();
    _loadVideoData();
  }

  void _loadVideoData() {
    // Get video data from VideoDataManager
    final videos = VideoDataManager.getVideos(widget.lessonName);
    if (videos.isNotEmpty && widget.subLessonIndex < videos.length) {
      _videoData = videos[widget.subLessonIndex];
    }
    _initializeVideo();
  }

  void _initializeVideo() async {
    if (_videoData == null) {
      setState(() => _hasError = true);
      return;
    }

    try {
      _videoController = VideoPlayerController.asset(_videoData!['videoUrl']);
      
      await _videoController.initialize();

      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
        _videoCompleted = false;
        _isCheckingCompletion = false;
      });
      
      _videoController.setLooping(false);
      _videoController.play();
      
      // Add listener to detect when video ends
      _videoController.addListener(() {
        if (_videoController.value.position == _videoController.value.duration && 
            _videoController.value.isPlaying == false) {
          if (!_videoCompleted && !_isCheckingCompletion) {
            setState(() {
              _videoCompleted = true;
            });
            
            // Auto-mark as complete when video ends
            _markAsComplete();
          }
        }
      });
      
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _markAsComplete() async {
    if (_isCheckingCompletion) return;
    
    setState(() {
      _isCheckingCompletion = true;
    });
    
    // Mark as completed in progress manager
    progressManager.markVideoCompleted(
      widget.lessonName, 
      widget.language, 
      widget.subLessonIndex, 
      _videoData!['title']
    );
    
    // Mark subtopic as completed
    progressManager.markSubtopicCompleted(
      widget.lessonName,
      _videoData!['title']
    );
    
    // Small delay to ensure progress is updated
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Check if lesson is fully completed
    bool isLessonComplete = _isLessonFullyCompleted(widget.lessonName);
    
    setState(() {
      _isCheckingCompletion = false;
    });
    
    if (isLessonComplete && !progressManager.isLessonCompleted(widget.lessonName)) {
      // Mark the lesson as completed
      progressManager.markLessonCompleted(widget.lessonName);
      
      // Show lesson completion dialog
      _showLessonCompletionDialog();
    } else {
      // Just show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Video marked as complete!',
            style: const TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Go back to lessons after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  bool _isLessonFullyCompleted(String lessonName) {
    final videos = VideoDataManager.getVideos(lessonName);
    if (videos.isEmpty) return false;
    
    int completedCount = 0;
    for (var video in videos) {
      if (progressManager.isSubtopicCompleted(lessonName, video['title'])) {
        completedCount++;
      }
    }
    
    return completedCount == videos.length;
  }

  void _showLessonCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '🎉 Lesson Complete!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 50),
                    const SizedBox(height: 10),
                    Text(
                      'You completed all videos in',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.lessonName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Would you like to take the comprehensive lesson exercise?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pop(context); // Go back to lessons
              },
              child: const Text(
                'Later',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToComprehensiveExercise();
              },
              child: const Text('Take Exercise'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToComprehensiveExercise() {
    // Determine which exercise screen to navigate to
    Widget? exerciseScreen;
    
    if (widget.lessonName == 'Whole Numbers') {
      exerciseScreen = WholeNumbersExerciseScreen(
        lessonName: widget.lessonName,
        language: widget.language,
      );
    } 
    else if (widget.lessonName == 'Comparison') {
      exerciseScreen = ComparisonComprehensiveExerciseScreen(
        lessonName: widget.lessonName,
        language: widget.language,
      );
    }
    else if (widget.lessonName == 'Addition' || 
             widget.lessonName == 'Subtraction' || 
             widget.lessonName == 'Multiplication' || 
             widget.lessonName == 'Division') {
      exerciseScreen = FundamentalOperationsExerciseScreen(
        lessonName: 'Fundamental Operations',
        language: widget.language,
      );
    }
    else if (widget.lessonName == 'Fraction') {
      // IMPORTANT: FractionExerciseScreen DOES NOT have subLessonIndex parameter
      exerciseScreen = FractionExerciseScreen(
        lessonName: widget.lessonName,
        language: widget.language,
      );
    }
    else if (widget.lessonName == 'Decimal Numbers') {
      exerciseScreen = DecimalExerciseScreen(
        lessonName: widget.lessonName,
        language: widget.language,
        subLessonIndex: 0, // DecimalExerciseScreen might need this
      );
    }
    else if (widget.lessonName == 'Percentage') {
      exerciseScreen = PercentageExerciseScreen(
        lessonName: widget.lessonName,
        language: widget.language,
        subLessonIndex: 0, // PercentageExerciseScreen might need this
      );
    }
    
    if (exerciseScreen != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => exerciseScreen!),
      ).then((_) {
        // After returning from exercise, go back to lessons
        if (mounted) {
          Navigator.pop(context);
        }
      });
    } else {
      // If no exercise screen found, just go back
      Navigator.pop(context);
    }
  }

  void _changePlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _videoController.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    _videoController.removeListener(() {});
    _videoController.dispose();
    super.dispose();
  }

  String get _videoTitle {
    if (widget.videoTitle != null) return widget.videoTitle!;
    if (_videoData != null) return _videoData!['title'];
    return '${widget.lessonName} Lesson';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.lessonName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _videoTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Video Player
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: _isVideoInitialized 
                              ? _videoController.value.aspectRatio 
                              : 16/9,
                          child: _hasError
                              ? _buildErrorWidget()
                              : _isVideoInitialized
                                  ? VideoPlayer(_videoController)
                                  : _buildLoadingWidget(),
                        ),
                        
                        if (_isVideoInitialized && !_hasError)
                          _buildVideoControls(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  
                  // MARK AS COMPLETE BUTTON
                  if (!_videoCompleted && _isVideoInitialized && !_hasError)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
                        ),
                        onPressed: _markAsComplete,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Mark as Complete',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Lora-Regular',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // COMPLETED INDICATOR
                  if (_videoCompleted)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 30,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Video Completed!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontFamily: 'Lora-Regular',
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),
                  
                  // Description
                  if (_videoData != null && _videoData!['description'] != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'About this lesson:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _videoData!['description'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'Poppins-Regular',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.yellow),
            SizedBox(height: 10),
            Text(
              'Loading video...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            const Text(
              'Video not available',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFF59D),
              ),
              onPressed: _initializeVideo,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Speed:', style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, size: 16, color: Colors.white),
                onSelected: _changePlaybackSpeed,
                itemBuilder: (context) => _speedOptions.map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x Speed', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    if (_videoController.value.isPlaying) {
                      _videoController.pause();
                    } else {
                      _videoController.play();
                    }
                  });
                },
              ),
              
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position - const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              
              Text(
                _formatDuration(_videoController.value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              
              Expanded(
                child: VideoProgressIndicator(
                  _videoController,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.yellow,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              
              Text(
                _formatDuration(_videoController.value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position + const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),

              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  _videoController.seekTo(Duration.zero);
                  _videoController.play();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

// ============ UPDATED FUNDAMENTAL OPERATIONS LESSONS SCREEN ============
class FundamentalOperationsLessonsScreen extends StatefulWidget {
  const FundamentalOperationsLessonsScreen({super.key});

  @override
  State<FundamentalOperationsLessonsScreen> createState() => _FundamentalOperationsLessonsScreenState();
}

class _FundamentalOperationsLessonsScreenState extends State<FundamentalOperationsLessonsScreen> {
  final Map<String, bool> _expandedLessons = {
    'addition': false,
    'subtraction': false,
    'multiplication': false,
    'division': false,
  };

  final List<Map<String, dynamic>> _lessons = [
    {
      'id': 'addition',
      'title': 'Addition',
      'description': 'Learn how to add numbers',
      'color': const Color(0xFFA8D5E3),
      'icon': Icons.add_circle,
      'subtopics': [
        {
          'title': 'Basic Addition Concepts',
          'learningObjectives': ['Illustrate addition as "putting together" sets'],
          'videoUrl': 'assets/Videos/BasicConcept.mp4',
          'duration': '0:58',
        },
        {
          'title': 'Adding with Objects',
          'learningObjectives': ['Add quantities up to 20 using concrete objects'],
          'videoUrl': 'assets/Videos/Addobject.mp4',
          'duration': '2:04',
        },
        {
          'title': 'Adding One to Two-Digit Numbers',
          'learningObjectives': ['Add two one to two-digit numbers'],
          'videoUrl': 'assets/Videos/Add1to2.mp4',
          'duration': '1:27',
        },
        {
          'title': 'Properties of Addition',
          'learningObjectives': ['Illustrate commutative, associative, and identity properties'],
          'videoUrl': 'assets/Videos/AdditionProperty.mp4',
          'duration': '2:15',
        },
        {
          'title': 'Adding Larger Numbers',
          'learningObjectives': ['Add up to 4-digit numbers with sums up to 1000'],
          'videoUrl': 'assets/Videos/AddLarge.mp4',
          'duration': '0:56',
        },
      ],
    },
    
    {
      'id': 'subtraction',
      'title': 'Subtraction',
      'description': 'Learn how to subtract numbers',
      'color': const Color(0xFFF5C6D6),
      'icon': Icons.remove_circle,
      'subtopics': [
        {
          'title': 'Understanding Subtraction',
          'learningObjectives': ['Recognize minus (-) sign'],
          'videoUrl': 'assets/Videos/UnderstandSubtract.mp4',
          'duration': '1:16',
        },
        {
          'title': 'Subtracting with Objects',
          'learningObjectives': ['Subtract quantities up to 20 using concrete objects'],
          'videoUrl': 'assets/Videos/SubtractObject.mp4',
          'duration': '0:56', 
        },
        {
          'title': 'Subtracting One to Two-Digit Numbers',
          'learningObjectives': ['Subtract two one to two-digit numbers'],
          'videoUrl': 'assets/Videos/Subtract1to2.mp4',
          'duration': '1:19',
        },
        {
          'title': 'Subtracting Larger Numbers',
          'learningObjectives': ['Subtract up to 4-digit numbers'],
          'videoUrl': 'assets/Videos/SubtractLarge.mp4',
          'duration': '0:51',
        },
      ],
    },
    
    {
      'id': 'multiplication',
      'title': 'Multiplication',
      'description': 'Learn how to multiply numbers',
      'color': const Color(0xFFC4B1E1),
      'icon': Icons.close,
      'subtopics': [
        {
          'title': 'Understanding Multiplication',
          'learningObjectives': ['Illustrate multiplication as repeated addition'],
          'videoUrl': 'assets/Videos/UnderstandMulti.mp4',
          'duration': '1:16',
        },
        {
          'title': 'Representing Multiplication',
          'learningObjectives': ['Represent multiplication of numbers'],
          'videoUrl': 'assets/Videos/RepresentMulti.mp4',
          'duration': '1:00',
        },
        {
          'title': 'Multiplying Numbers',
          'learningObjectives': ['Multiply two one to two-digit numbers'],
          'videoUrl': 'assets/Videos/MultiNumbers.mp4',
          'duration': '1:35',
        },
        {
          'title': 'Properties of Multiplication',
          'learningObjectives': ['Illustrate the properties of multiplication'],
          'videoUrl': 'assets/Videos/MultiProperty.mp4',
          'duration': '1:50',
        },
      ],
    },
    
    {
      'id': 'division',
      'title': 'Division',
      'description': 'Learn how to divide numbers',
      'color': const Color(0xFFA8D5BA),
      'icon': Icons.percent,
      'subtopics': [
        {
          'title': 'Understanding Division',
          'learningObjectives': ['Represents division as equal sharing'],
          'videoUrl': 'assets/Videos/Division.mp4',
          'duration': '0:56',
        },
        {
          'title': 'Division as Repeated Subtraction',
          'learningObjectives': ['Illustrate division as repeated subtraction'],
          'videoUrl': 'assets/Videos/DivisionRepeated.mp4',
          'duration': '1:23',
        },
        {
          'title': 'Dividing Numbers',
          'learningObjectives': ['Divide two one to two-digit numbers'],
          'videoUrl': 'assets/Videos/DividingNumbers.mp4',
          'duration': '0:44',
        },
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    progressManager.unlockStream.listen((topicName) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  bool _isLessonUnlocked(String lessonTitle) {
    if (lessonTitle == 'Addition') {
      return progressManager.isTopicUnlocked('Fundamental Operations');
    }
    
    if (lessonTitle == 'Subtraction') {
      return _isLessonFullyCompleted('Addition');
    }
    
    if (lessonTitle == 'Multiplication') {
      return _isLessonFullyCompleted('Subtraction');
    }
    
    if (lessonTitle == 'Division') {
      return _isLessonFullyCompleted('Multiplication');
    }
    
    return false;
  }

  bool _isLessonFullyCompleted(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return false;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount == subtopics.length;
    } catch (e) {
      return false;
    }
  }

  bool _isVideoUnlocked(String lessonTitle, int videoIndex) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (videoIndex == 0) {
        return _isLessonUnlocked(lessonTitle);
      }
      
      final previousVideo = subtopics[videoIndex - 1];
      return progressManager.isSubtopicCompleted(lessonTitle, previousVideo['title']);
    } catch (e) {
      return false;
    }
  }

  double _getLessonProgress(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return 0;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount / subtopics.length;
    } catch (e) {
      return 0;
    }
  }

  int _getCompletedCount(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount;
    } catch (e) {
      return 0;
    }
  }

  void _toggleLesson(String lessonId) {
    setState(() {
      _expandedLessons[lessonId] = !(_expandedLessons[lessonId] ?? false);
    });
  }

  void _navigateToVideo(String lessonTitle, Map<String, dynamic> subtopic, bool isUnlocked) {
    if (!isUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete the previous video first!',
            style: const TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    String learningObjectives = (subtopic['learningObjectives'] as List).join('\n• ');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FundamentalOperationsVideoScreen(
          lessonTitle: lessonTitle,
          videoTitle: subtopic['title'],
          videoUrl: subtopic['videoUrl'],
          learningObjective: 'Learning Objectives:\n• $learningObjectives',
        ),
      ),
    ).then((_) {
      setState(() {});
      _checkFundamentalOperationsCompletion();
    });
  }

  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FundamentalOperationsExerciseScreen(
        lessonName: 'Fundamental Operations',
        language: 'English',
      )),
    ).then((_) {
      setState(() {});
    });
  }

  bool _areAllLessonsCompleted() {
    return _isLessonFullyCompleted('Addition') &&
           _isLessonFullyCompleted('Subtraction') &&
           _isLessonFullyCompleted('Multiplication') &&
           _isLessonFullyCompleted('Division');
  }

  void _checkFundamentalOperationsCompletion() {
    if (_areAllLessonsCompleted()) {
      if (!progressManager.isTopicCompleted('Fundamental Operations')) {
        progressManager.markTopicCompleted('Fundamental Operations');
      }
      
      // Unlock Fraction
      if (!progressManager.isTopicUnlocked('Fraction')) {
        progressManager.unlockTopic('Fraction');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔓 Fraction is now unlocked!',
              style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isTopicUnlocked = progressManager.isTopicUnlocked('Fundamental Operations');
    final bool allLessonsCompleted = _areAllLessonsCompleted();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Fundamental Operations',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isTopicUnlocked 
                    ? const Color(0xFFF5C6D6).withOpacity(0.3) 
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isTopicUnlocked ? const Color(0xFFF5C6D6) : Colors.grey.shade400, 
                  width: 2
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fundamental Operations',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                      color: isTopicUnlocked ? Colors.black : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isTopicUnlocked 
                        ? 'Learn addition, subtraction, multiplication, and division'
                        : '🔒 Complete Number Values to unlock',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: isTopicUnlocked ? Colors.black54 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            if (allLessonsCompleted)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.emoji_events, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(
                          'Congratulations!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You completed all Fundamental Operations lessons!\nNow test your knowledge with the comprehensive exercise.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _navigateToComprehensiveExercise,
                        child: const Text(
                          'Take Comprehensive Topic Exercise',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            ..._lessons.map((lesson) {
              final isLessonUnlocked = _isLessonUnlocked(lesson['title'] as String);
              final isLessonCompleted = progressManager.isLessonCompleted(lesson['title'] as String);
              final isFullyCompleted = _isLessonFullyCompleted(lesson['title'] as String);
              
              return _buildDropdownLesson(lesson, isLessonUnlocked, isLessonCompleted, isFullyCompleted);
            }).toList(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownLesson(Map<String, dynamic> lesson, bool isLessonUnlocked, bool isLessonCompleted, bool isFullyCompleted) {
    final isExpanded = _expandedLessons[lesson['id'] as String] ?? false;
    final subtopics = lesson['subtopics'] as List;
    final lessonTitle = lesson['title'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? lesson['color'] as Color : Colors.grey.shade400),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLessonUnlocked ? () => _toggleLesson(lesson['id'] as String) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isLessonCompleted ? Colors.green.withOpacity(0.2) : (isLessonUnlocked ? lesson['color'] as Color : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: isLessonCompleted
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 30)
                          : Icon(
                              isLessonUnlocked ? lesson['icon'] as IconData : Icons.lock,
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lessonTitle,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${subtopics.length} subtopics',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Poppins-Regular',
                              color: isLessonUnlocked ? Colors.grey[600] : Colors.grey.shade500,
                            ),
                          ),
                          
                          if (!isLessonUnlocked && lessonTitle != 'Addition')
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Complete previous lesson first',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          if (isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Completed',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (isLessonUnlocked)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey[400]!),
                        ),
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.black,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded && isLessonUnlocked)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border(top: BorderSide(color: lesson['color'] as Color, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson['description'] as String,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  LinearProgressIndicator(
                    value: _getLessonProgress(lessonTitle),
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_getCompletedCount(lessonTitle)}/${subtopics.length} videos completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  
                  const SizedBox(height: 15),
                  
                  ...List.generate(subtopics.length, (index) {
                    final subtopic = subtopics[index] as Map<String, dynamic>;
                    final isVideoUnlocked = _isVideoUnlocked(lessonTitle, index);
                    final isVideoCompleted = progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'] as String);
                    
                    return _buildSubtopicItem(
                      lessonTitle: lessonTitle,
                      subtopic: subtopic,
                      index: index,
                      isUnlocked: isVideoUnlocked,
                      isCompleted: isVideoCompleted,
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubtopicItem({
    required String lessonTitle,
    required Map<String, dynamic> subtopic,
    required int index,
    required bool isUnlocked,
    required bool isCompleted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnlocked ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCompleted ? Colors.green : (isUnlocked ? Colors.grey[300]! : Colors.grey.shade300),
          width: isCompleted ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? () {
            if (isUnlocked) {
              _navigateToVideo(lessonTitle, subtopic, isUnlocked);
            }
          } : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green.withOpacity(0.2) : (isUnlocked ? _getLessonColor(lessonTitle).withOpacity(0.2) : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted ? Colors.green : (isUnlocked ? _getLessonColor(lessonTitle) : Colors.grey.shade400),
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, size: 16, color: Colors.green)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isUnlocked ? Colors.black : Colors.grey.shade600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subtopic['title'] as String,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 12, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                subtopic['duration'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!isUnlocked && !isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.orange.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Locked',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFFFF59D) : Colors.grey.shade300),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted ? Colors.green.shade700 : (isUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : (isUnlocked ? Icons.play_arrow : Icons.lock),
                        color: isCompleted ? Colors.white : (isUnlocked ? Colors.black : Colors.grey.shade600),
                        size: 16,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (subtopic['learningObjectives'] as List).map((objective) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                objective as String,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getLessonColor(String lessonTitle) {
    switch (lessonTitle) {
      case 'Addition':
        return const Color(0xFFA8D5E3);
      case 'Subtraction':
        return const Color(0xFFF5C6D6);
      case 'Multiplication':
        return const Color(0xFFC4B1E1);
      case 'Division':
        return const Color(0xFFA8D5BA);
      default:
        return Colors.grey;
    }
  }
}

// ============ UPDATED FUNDAMENTAL OPERATIONS VIDEO SCREEN - AUTO BACK ============
class FundamentalOperationsVideoScreen extends StatefulWidget {
  final String lessonTitle;
  final String videoTitle;
  final String videoUrl;
  final String? learningObjective;

  const FundamentalOperationsVideoScreen({
    super.key,
    required this.lessonTitle,
    required this.videoTitle,
    required this.videoUrl,
    this.learningObjective,
  });

  @override
  State<FundamentalOperationsVideoScreen> createState() => _FundamentalOperationsVideoScreenState();
}

class _FundamentalOperationsVideoScreenState extends State<FundamentalOperationsVideoScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _videoCompleted = false;
  bool _isCheckingCompletion = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset(widget.videoUrl);
      await _videoController.initialize();

      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
        _videoCompleted = false;
      });
      
      _videoController.setLooping(false);
      _videoController.play();
      
      _videoController.addListener(() {
        if (_videoController.value.position == _videoController.value.duration && 
            _videoController.value.isPlaying == false) {
          if (!_videoCompleted && !_isCheckingCompletion) {
            setState(() {
              _videoCompleted = true;
            });
            _markAsComplete();
          }
        }
      });
      
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _markAsComplete() async {
    if (_isCheckingCompletion) return;
    
    setState(() => _isCheckingCompletion = true);
    
    // Mark video as completed
    progressManager.markVideoCompleted(
      widget.lessonTitle, 
      'English', 
      0, 
      widget.videoTitle
    );
    
    // Mark subtopic as completed
    progressManager.markSubtopicCompleted(
      widget.lessonTitle,
      widget.videoTitle
    );
    
    // Small delay to ensure progress is updated
    await Future.delayed(const Duration(milliseconds: 300));
    
    setState(() => _isCheckingCompletion = false);
    
    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Video marked as complete!',
            style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    
    // Check if all Fundamental Operations lessons are completed
    _checkFundamentalOperationsCompletion();
    
    // AUTO BACK TO LESSONS AFTER SHORT DELAY
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      Navigator.pop(context); // Go back to lessons list
    }
  }

  void _checkFundamentalOperationsCompletion() {
    bool additionCompleted = progressManager.isLessonCompleted('Addition');
    bool subtractionCompleted = progressManager.isLessonCompleted('Subtraction');
    bool multiplicationCompleted = progressManager.isLessonCompleted('Multiplication');
    bool divisionCompleted = progressManager.isLessonCompleted('Division');
    
    if (additionCompleted && subtractionCompleted && multiplicationCompleted && divisionCompleted) {
      progressManager.markTopicCompleted('Fundamental Operations');
      progressManager.unlockTopic('Fraction');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔓 Fraction is now unlocked!',
              style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _changePlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _videoController.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    _videoController.removeListener(() {});
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.lessonTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.videoTitle,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Lora-Regular'),
                  ),
                  const SizedBox(height: 10),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: _isVideoInitialized ? _videoController.value.aspectRatio : 16/9,
                          child: _hasError
                              ? _buildErrorWidget()
                              : _isVideoInitialized
                                  ? VideoPlayer(_videoController)
                                  : _buildLoadingWidget(),
                        ),
                        if (_isVideoInitialized && !_hasError) _buildVideoControls(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  
                  if (widget.learningObjective != null && widget.learningObjective!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.school, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Learning Objective:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                  fontFamily: 'Lora-Regular',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.learningObjective!,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Poppins-Regular',
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                  
                  if (!_videoCompleted && _isVideoInitialized && !_hasError)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 5,
                        ),
                        onPressed: _markAsComplete,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Mark as Complete',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Lora-Regular'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  if (_videoCompleted)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.check_circle, color: Colors.green, size: 30),
                          SizedBox(width: 10),
                          Text(
                            'Video Completed!',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green, fontFamily: 'Lora-Regular'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.yellow),
            SizedBox(height: 10),
            Text('Loading video...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            const Text('Video not available', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFF59D)),
              onPressed: _initializeVideo,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Speed:', style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Text('${_playbackSpeed}x', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, size: 16, color: Colors.white),
                onSelected: _changePlaybackSpeed,
                itemBuilder: (context) => _speedOptions.map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x Speed', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(_videoController.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _videoController.value.isPlaying ? _videoController.pause() : _videoController.play();
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position - const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              Text(_formatDuration(_videoController.value.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: VideoProgressIndicator(
                  _videoController,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: Colors.yellow, bufferedColor: Colors.grey, backgroundColor: Colors.white24),
                ),
              ),
              Text(_formatDuration(_videoController.value.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position + const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  _videoController.seekTo(Duration.zero);
                  _videoController.play();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

// ============ FUNDAMENTAL OPERATIONS COMPREHENSIVE EXERCISE (15 ITEMS) ============
/// Thin wrapper â€” exercise logic lives in the [exercise_feature.ExerciseScreen] module.
class FundamentalOperationsExerciseScreen extends StatelessWidget {
  final String lessonName;
  final String language;
  const FundamentalOperationsExerciseScreen(
      {super.key, required this.lessonName, required this.language});
  @override
  Widget build(BuildContext context) {
    // Progress is recorded under all four operation lesson names; aggregate
    // them to determine auto-start eligibility for this consolidated exercise.
    final flags = aggregateProgressFlags(
      FundamentalOperationsQuestions.allLessonNames,
      completedCount: progressManager.getCompletedExercisesForLesson,
      hasPassed: progressManager.hasEverPassedExercise,
    );
    // Collect subtopics from all four operation lessons for richer AI context.
    final allSubtopics = FundamentalOperationsQuestions.allLessonNames
        .expand((n) => TopicsData.getSubtopicsByLessonTitle(n))
        .toList();
    final foTopic = TopicsData.getTopics().firstWhere(
      (t) => t.id == 'topic2',
      orElse: () => TopicsData.getTopics().first,
    );
    return exercise_feature.ExerciseScreen(
      lessonName: lessonName,
      language: language,
      title: 'Fundamental Operations Exercise',
      questions: FundamentalOperationsQuestions.all,
      allLessonNames: FundamentalOperationsQuestions.allLessonNames,
      showAiRemediation: true,
      autoStartRemediation: shouldAutoStartRemediation(
        hasAnyAttempt: flags.hasAnyAttempt,
        hasAnyPass: flags.hasAnyPass,
      ),
      lessonId: 'lesson2_1',
      aiLessonContext: buildAiLessonContext(
        lessonTitle: 'Fundamental Operations',
        subtopics: allSubtopics,
        topicId: 'topic2',
        topicTitle: foTopic.title,
      ),
      onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>
          progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),
      onExerciseInsightsSaved: (names, summary, topics) =>
          progressManager.saveLessonExerciseInsights(
            names,
            summary: summary,
            recommendedSubtopics: topics,
          ),
    );
  }
}

class FractionLessonsScreen extends StatefulWidget {
  const FractionLessonsScreen({super.key});

  @override
  State<FractionLessonsScreen> createState() => _FractionLessonsScreenState();
}

class _FractionLessonsScreenState extends State<FractionLessonsScreen> {
  final Map<String, bool> _expandedLessons = {
    'fraction': false,
  };

  final List<Map<String, dynamic>> _lessons = [
    {
      'id': 'fraction',
      'title': 'Fraction',
      'description': 'Learn about fractions - parts of a whole',
      'color': const Color(0xFFC4B1E1),
      'icon': Icons.pie_chart,
      'subtopics': [
        {
          'title': 'Recognizing Fractions',
          'learningObjectives': ['Recognize and identify ¼, ½, ¾ of a whole object'],
          'videoUrl': 'assets/Videos/FractionsRecognizing.mp4',
          'duration': '1:04',
        },
        {
          'title': 'Describing Fractions',
          'learningObjectives': ['Describe a whole and ¼, ½ and ¾ of a whole'],
          'videoUrl': 'assets/Videos/FractionsDescribing.mp4',
          'duration': '1:33',
        },
        {
          'title': 'Reading Fractions',
          'learningObjectives': ['Read fractions correctly'],
          'videoUrl': 'assets/Videos/FractionsReading.mp4',
          'duration': '0:48',
        },
        {
          'title': 'Comparing Fractions',
          'learningObjectives': ['Compare fractions using relation symbols (<, >, =)'],
          'videoUrl': 'assets/Videos/FractionsComparing.mp4',
          'duration': '1:10',
        },
        {
          'title': 'Ordering Fractions',
          'learningObjectives': ['Arrange fractions in increasing and decreasing order'],
          'videoUrl': 'assets/Videos/FractionsOrdering.mp4',
          'duration': '0:56',
        },
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    progressManager.unlockStream.listen((topicName) {
      if (mounted && topicName == 'Fraction') {
        setState(() {});
      }
    });
    _checkIfUnlocked();
  }

  void _checkIfUnlocked() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!progressManager.isTopicUnlocked('Fraction') && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Complete all lessons in Fundamental Operations first!',
              style: const TextStyle(fontFamily: 'Poppins-Regular'),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  bool _isLessonUnlocked(String lessonTitle) {
    return progressManager.isTopicUnlocked('Fraction');
  }

  bool _isLessonFullyCompleted(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return false;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount == subtopics.length;
    } catch (e) {
      return false;
    }
  }

  bool _isVideoUnlocked(String lessonTitle, int videoIndex) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (videoIndex == 0) {
        return _isLessonUnlocked(lessonTitle);
      }
      
      final previousVideo = subtopics[videoIndex - 1];
      return progressManager.isSubtopicCompleted(lessonTitle, previousVideo['title']);
    } catch (e) {
      return false;
    }
  }

  double _getLessonProgress(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return 0;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount / subtopics.length;
    } catch (e) {
      return 0;
    }
  }

  int _getCompletedCount(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount;
    } catch (e) {
      return 0;
    }
  }

  void _toggleLesson(String lessonId) {
    setState(() {
      _expandedLessons[lessonId] = !(_expandedLessons[lessonId] ?? false);
    });
  }

  void _navigateToVideo(String lessonTitle, Map<String, dynamic> subtopic) {
    String learningObjectives = (subtopic['learningObjectives'] as List).join('\n• ');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FractionVideoScreen(
          lessonTitle: lessonTitle,
          videoTitle: subtopic['title'],
          videoUrl: subtopic['videoUrl'],
          learningObjective: 'Learning Objectives:\n• $learningObjectives',
        ),
      ),
    ).then((_) {
      setState(() {});
      _checkFractionCompletion();
    });
  }

  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FractionExerciseScreen(
        lessonName: 'Fraction',
        language: 'English',
      )),
    ).then((_) {
      setState(() {});
    });
  }

  void _checkFractionCompletion() {
    bool fractionCompleted = _isLessonFullyCompleted('Fraction');
    
    if (fractionCompleted) {
      if (!progressManager.isTopicCompleted('Fraction')) {
        progressManager.markTopicCompleted('Fraction');
      }
      
      if (!progressManager.isTopicUnlocked('Decimal Numbers')) {
        progressManager.unlockTopic('Decimal Numbers');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔓 Decimal Numbers is now unlocked!',
              style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUnlocked = progressManager.isTopicUnlocked('Fraction');
    final bool isLessonCompleted = progressManager.isLessonCompleted('Fraction');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Fraction Lessons',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUnlocked 
                    ? const Color(0xFFC4B1E1).withOpacity(0.3) 
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUnlocked ? const Color(0xFFC4B1E1) : Colors.grey.shade400, 
                  width: 2
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fraction',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                      color: isUnlocked ? Colors.black : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isUnlocked 
                        ? 'Learn about fractions - parts of a whole'
                        : '🔒 Complete all lessons in Fundamental Operations to unlock',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: isUnlocked ? Colors.black54 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            if (isLessonCompleted)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.emoji_events, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(
                          'Congratulations!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You completed all Fraction lessons!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _navigateToComprehensiveExercise,
                        child: const Text(
                          'Take Comprehensive Topic Exercise',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            ..._lessons.map((lesson) {
              final isLessonUnlocked = _isLessonUnlocked(lesson['title']);
              final isLessonCompleted = progressManager.isLessonCompleted(lesson['title']);
              final isFullyCompleted = _isLessonFullyCompleted(lesson['title']);
              
              return _buildDropdownLesson(lesson, isLessonUnlocked, isLessonCompleted, isFullyCompleted);
            }).toList(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownLesson(Map<String, dynamic> lesson, bool isLessonUnlocked, bool isLessonCompleted, bool isFullyCompleted) {
    final isExpanded = _expandedLessons[lesson['id']] ?? false;
    final subtopics = lesson['subtopics'] as List;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? lesson['color'] : Colors.grey.shade400),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLessonUnlocked ? () => _toggleLesson(lesson['id']) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isLessonCompleted ? Colors.green.withOpacity(0.2) : (isLessonUnlocked ? lesson['color'] : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: isLessonCompleted
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 30)
                          : Icon(
                              isLessonUnlocked ? lesson['icon'] : Icons.lock,
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson['title'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${subtopics.length} subtopics',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Poppins-Regular',
                              color: isLessonUnlocked ? Colors.grey[600] : Colors.grey.shade500,
                            ),
                          ),
                          
                          if (isFullyCompleted && !isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.assignment, size: 10, color: Colors.blue.shade700),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Exercise Available',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          if (!isLessonUnlocked)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Complete Fundamental Operations first',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Completed',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (isLessonUnlocked)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey[400]!),
                        ),
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.black,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          if (isExpanded && isLessonUnlocked)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border(top: BorderSide(color: lesson['color'], width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson['description'],
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  LinearProgressIndicator(
                    value: _getLessonProgress(lesson['title']),
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_getCompletedCount(lesson['title'])}/${subtopics.length} videos completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  
                  const SizedBox(height: 15),
                  
                  ...List.generate(subtopics.length, (index) {
                    final subtopic = subtopics[index];
                    final isVideoUnlocked = _isVideoUnlocked(lesson['title'], index);
                    final isVideoCompleted = progressManager.isSubtopicCompleted(lesson['title'], subtopic['title']);
                    
                    return _buildSubtopicItem(
                      lessonTitle: lesson['title'],
                      subtopic: subtopic,
                      index: index,
                      isUnlocked: isVideoUnlocked,
                      isCompleted: isVideoCompleted,
                    );
                  }),
                  
                  if (isFullyCompleted && !isLessonCompleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _navigateToComprehensiveExercise,
                          child: const Text(
                            'Take Comprehensive Lesson Exercise',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubtopicItem({
    required String lessonTitle,
    required Map<String, dynamic> subtopic,
    required int index,
    required bool isUnlocked,
    required bool isCompleted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnlocked ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCompleted ? Colors.green : (isUnlocked ? Colors.grey[300]! : Colors.grey.shade300),
          width: isCompleted ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? () {
            if (isUnlocked) {
              _navigateToVideo(lessonTitle, subtopic);
            }
          } : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green.withOpacity(0.2) : (isUnlocked ? const Color(0xFFC4B1E1).withOpacity(0.2) : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFC4B1E1) : Colors.grey.shade400),
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, size: 16, color: Colors.green)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isUnlocked ? Colors.black : Colors.grey.shade600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subtopic['title'],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 12, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                subtopic['duration'],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!isUnlocked && !isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.orange.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Locked',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFFFF59D) : Colors.grey.shade300),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted ? Colors.green.shade700 : (isUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : (isUnlocked ? Icons.play_arrow : Icons.lock),
                        color: isCompleted ? Colors.white : (isUnlocked ? Colors.black : Colors.grey.shade600),
                        size: 16,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (subtopic['learningObjectives'] as List).map((objective) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                objective,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ UPDATED FRACTION VIDEO SCREEN ============
class FractionVideoScreen extends StatefulWidget {
  final String lessonTitle;
  final String videoTitle;
  final String videoUrl;
  final String? learningObjective;

  const FractionVideoScreen({
    super.key,
    required this.lessonTitle,
    required this.videoTitle,
    required this.videoUrl,
    this.learningObjective,
  });

  @override
  State<FractionVideoScreen> createState() => _FractionVideoScreenState();
}

class _FractionVideoScreenState extends State<FractionVideoScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _videoCompleted = false;
  bool _isCheckingCompletion = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset(widget.videoUrl);
      await _videoController.initialize();

      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
        _videoCompleted = false;
      });
      
      _videoController.setLooping(false);
      _videoController.play();
      
      _videoController.addListener(() {
        if (_videoController.value.position == _videoController.value.duration && 
            _videoController.value.isPlaying == false) {
          if (!_videoCompleted && !_isCheckingCompletion) {
            setState(() {
              _videoCompleted = true;
            });
            _markAsComplete();
          }
        }
      });
      
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _markAsComplete() async {
    if (_isCheckingCompletion) return;
    
    setState(() {
      _isCheckingCompletion = true;
    });
    
    // Mark video as completed
    progressManager.markVideoCompleted(
      widget.lessonTitle, 
      'English', 
      0, 
      widget.videoTitle
    );
    
    // Mark subtopic as completed
    progressManager.markSubtopicCompleted(
      widget.lessonTitle,
      widget.videoTitle
    );
    
    // Small delay to ensure progress is updated
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Check if lesson is fully completed
    bool isLessonComplete = progressManager.isLessonFullyCompleted(widget.lessonTitle);
    
    setState(() {
      _isCheckingCompletion = false;
    });
    
    if (isLessonComplete && !progressManager.isLessonCompleted(widget.lessonTitle)) {
      // Mark the lesson as completed
      progressManager.markLessonCompleted(widget.lessonTitle);
      
      // Show completion message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎉 You completed all videos in ${widget.lessonTitle}!',
            style: const TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Check if Fraction topic is now fully completed
      _checkFractionCompletion();
    } else {
      // Just show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Video marked as complete!',
            style: const TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _checkFractionCompletion() {
    // Check if Fraction lesson is completed
    bool fractionCompleted = progressManager.isLessonCompleted('Fraction');
    
    if (fractionCompleted) {
      // Mark Fraction topic as completed
      progressManager.markTopicCompleted('Fraction');
      
      // Unlock Decimal Numbers
      progressManager.unlockTopic('Decimal Numbers');
      
      // Show comprehensive exercise dialog
      _showComprehensiveExerciseDialog();
    }
  }

  void _showComprehensiveExerciseDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '🎉 Topic Complete!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 50),
                    const SizedBox(height: 10),
                    const Text(
                      'You completed all lessons in',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Fraction',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Now test your knowledge with the comprehensive topic exercise!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Later', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToComprehensiveExercise();
              },
              child: const Text('Take Exercise'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FractionExerciseScreen(
        lessonName: 'Fraction',
        language: 'English',
      )),
    ).then((_) {
      // After returning from exercise, go back to lessons
      Navigator.pop(context);
    });
  }

  void _changePlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _videoController.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    _videoController.removeListener(() {});
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.lessonTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.videoTitle,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Lora-Regular'),
                  ),
                  const SizedBox(height: 10),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: _isVideoInitialized ? _videoController.value.aspectRatio : 16/9,
                          child: _hasError
                              ? _buildErrorWidget()
                              : _isVideoInitialized
                                  ? VideoPlayer(_videoController)
                                  : _buildLoadingWidget(),
                        ),
                        if (_isVideoInitialized && !_hasError) _buildVideoControls(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  
                  if (widget.learningObjective != null && widget.learningObjective!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.school, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Learning Objective:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                  fontFamily: 'Lora-Regular',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.learningObjective!,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Poppins-Regular',
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                  
                  if (!_videoCompleted && _isVideoInitialized && !_hasError)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 5,
                        ),
                        onPressed: _markAsComplete,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Mark as Complete',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Lora-Regular'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  if (_videoCompleted)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.check_circle, color: Colors.green, size: 30),
                          SizedBox(width: 10),
                          Text(
                            'Video Completed!',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green, fontFamily: 'Lora-Regular'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.yellow),
            SizedBox(height: 10),
            Text('Loading video...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            const Text('Video not available', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFF59D)),
              onPressed: _initializeVideo,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Speed:', style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Text('${_playbackSpeed}x', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, size: 16, color: Colors.white),
                onSelected: _changePlaybackSpeed,
                itemBuilder: (context) => _speedOptions.map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x Speed', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(_videoController.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _videoController.value.isPlaying ? _videoController.pause() : _videoController.play();
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position - const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              Text(_formatDuration(_videoController.value.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: VideoProgressIndicator(
                  _videoController,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: Colors.yellow, bufferedColor: Colors.grey, backgroundColor: Colors.white24),
                ),
              ),
              Text(_formatDuration(_videoController.value.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position + const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  _videoController.seekTo(Duration.zero);
                  _videoController.play();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

// ============ UPDATED FRACTION EXERCISE SCREEN (with squares only) ============
/// Thin wrapper â€” exercise logic lives in the [exercise_feature.ExerciseScreen] module.
class FractionExerciseScreen extends StatelessWidget {
  final String lessonName;
  final String language;
  const FractionExerciseScreen(
      {super.key, required this.lessonName, required this.language});
  @override
  Widget build(BuildContext context) {
    final flags = aggregateProgressFlags(
      [lessonName],
      completedCount: progressManager.getCompletedExercisesForLesson,
      hasPassed: progressManager.hasEverPassedExercise,
    );
    final lesson = TopicsData.getLessonByTitle(lessonName);
    final topic = lesson != null
        ? TopicsData.getTopics().firstWhere(
            (t) => t.id == lesson.topicId,
            orElse: () => TopicsData.getTopics().first,
          )
        : null;
    return exercise_feature.ExerciseScreen(
      lessonName: lessonName,
      language: language,
      title: 'Fraction Exercise',
      questions: FractionsQuestions.all,
      showAiRemediation: true,
      autoStartRemediation: shouldAutoStartRemediation(
        hasAnyAttempt: flags.hasAnyAttempt,
        hasAnyPass: flags.hasAnyPass,
      ),
      lessonId: lesson?.id ?? lessonName,
      aiLessonContext: buildAiLessonContext(
        lessonTitle: lessonName,
        subtopics: lesson?.subtopics ?? [],
        topicId: lesson?.topicId,
        topicTitle: topic?.title,
      ),
      onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>
          progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),
      onExerciseInsightsSaved: (names, summary, topics) =>
          progressManager.saveLessonExerciseInsights(
            names,
            summary: summary,
            recommendedSubtopics: topics,
          ),
    );
  }
}

class DecimalNumbersLessonsScreen extends StatefulWidget {
  const DecimalNumbersLessonsScreen({super.key});

  @override
  State<DecimalNumbersLessonsScreen> createState() => _DecimalNumbersLessonsScreenState();
}

class _DecimalNumbersLessonsScreenState extends State<DecimalNumbersLessonsScreen> {
  // Track which lessons are expanded
  final Map<String, bool> _expandedLessons = {
    'decimal': false,
  };

  // Lesson data structure - UPDATED with only 2 subtopics
  final List<Map<String, dynamic>> _lessons = [
    {
      'id': 'decimal',
      'title': 'Decimal Numbers',
      'description': 'Learn about decimal numbers - conversion and place value',
      'color': const Color(0xFFFFD8A8), // Orange color
      'icon': Icons.numbers,
      'subtopics': [
        {
          'title': 'Decimal to Fraction Conversion',
          'learningObjectives': [
            'Convert 0.125, 0.5, 0.75 to fractional form',
            'Understand the relationship between decimals and fractions',
          ],
          'videoUrl': 'assets/Videos/DecimalstoFraction.mp4',
          'duration': '1:08',
        },
        {
          'title': 'Place Value in Decimals',
          'learningObjectives': [
            'Identify the place value of every digit in decimal numbers',
            'Understand tenths, hundredths, thousandths places',
          ],
          'videoUrl': 'assets/Videos/DecimalPlaceValue.mp4',
          'duration': '1:33',
        },
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    // Listen for unlock events
    progressManager.unlockStream.listen((topicName) {
      if (mounted && topicName == 'Decimal Numbers') {
        setState(() {});
      }
    });
    // Check if Decimal Numbers is unlocked
    _checkIfUnlocked();
  }

  void _checkIfUnlocked() {
    if (!progressManager.isTopicUnlocked('Decimal Numbers')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete all lessons in Fraction first!',
            style: TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  // Check if lesson is unlocked (Decimal Numbers only has one lesson)
  bool _isLessonUnlocked(String lessonTitle) {
    return progressManager.isTopicUnlocked('Decimal Numbers');
  }

  // Check if ALL videos in a lesson are completed
  bool _isLessonFullyCompleted(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return false;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount == subtopics.length;
    } catch (e) {
      return false;
    }
  }

  // Check if video is unlocked (sequential within lesson)
  bool _isVideoUnlocked(String lessonTitle, int videoIndex) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (videoIndex == 0) {
        return _isLessonUnlocked(lessonTitle);
      }
      
      final previousVideo = subtopics[videoIndex - 1];
      return progressManager.isSubtopicCompleted(lessonTitle, previousVideo['title']);
    } catch (e) {
      return false;
    }
  }

  // Get lesson progress
  double _getLessonProgress(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return 0;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount / subtopics.length;
    } catch (e) {
      return 0;
    }
  }

  // Get completed count
  int _getCompletedCount(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount;
    } catch (e) {
      return 0;
    }
  }

  void _toggleLesson(String lessonId) {
    setState(() {
      _expandedLessons[lessonId] = !(_expandedLessons[lessonId] ?? false);
    });
  }

  void _navigateToVideo(String lessonTitle, Map<String, dynamic> subtopic) {
    // Build learning objectives text
    String learningObjectives = subtopic['learningObjectives'].join('\n• ');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DecimalVideoScreen(
          lessonTitle: lessonTitle,
          videoTitle: subtopic['title'],
          videoUrl: subtopic['videoUrl'],
          learningObjective: 'Learning Objectives:\n• $learningObjectives',
        ),
      ),
    ).then((_) {
      setState(() {});
      
      // Check if Decimal Numbers topic is now fully completed
      _checkDecimalCompletion();
    });
  }

  // Navigate to comprehensive exercise
  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DecimalExerciseScreen(
        lessonName: 'Decimal Numbers',
        language: 'English',
        subLessonIndex: 0,
      )),
    ).then((_) {
      setState(() {});
    });
  }

  // Check if Decimal Numbers topic is fully completed
  void _checkDecimalCompletion() {
    bool decimalCompleted = progressManager.isLessonCompleted('Decimal Numbers');
    
    if (decimalCompleted) {
      // Mark Decimal Numbers topic as completed
      progressManager.markTopicCompleted('Decimal Numbers');
      
      // Unlock next topic (Percentage)
      progressManager.unlockTopic('Percentage');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🔓 Percentage is now unlocked!',
            style: TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUnlocked = progressManager.isTopicUnlocked('Decimal Numbers');
    final bool isLessonCompleted = progressManager.isLessonCompleted('Decimal Numbers');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Decimal Numbers',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUnlocked 
                    ? const Color(0xFFFFD8A8).withOpacity(0.3) 
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUnlocked ? const Color(0xFFFFD8A8) : Colors.grey.shade400, 
                  width: 2
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Decimal Numbers',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                      color: isUnlocked ? Colors.black : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isUnlocked 
                        ? 'Learn about decimal numbers - conversion and place value'
                        : '🔒 Complete all lessons in Fraction to unlock',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: isUnlocked ? Colors.black54 : Colors.grey.shade600,
                    ),
                  ),
                  if (!isUnlocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, color: Colors.orange.shade700, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'LOCKED',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // ============ SHOW EXERCISE BUTTON WHEN LESSON IS COMPLETED ============
            if (isLessonCompleted)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.emoji_events, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(
                          'Congratulations!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You completed all Decimal Numbers lessons!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _navigateToComprehensiveExercise,
                        child: const Text(
                          'Take Comprehensive Topic Exercise',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Lessons List with Dropdowns
            ..._lessons.map((lesson) {
              final isLessonUnlocked = _isLessonUnlocked(lesson['title']);
              final isLessonCompleted = progressManager.isLessonCompleted(lesson['title']);
              final isFullyCompleted = _isLessonFullyCompleted(lesson['title']);
              
              return _buildDropdownLesson(lesson, isLessonUnlocked, isLessonCompleted, isFullyCompleted);
            }).toList(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownLesson(Map<String, dynamic> lesson, bool isLessonUnlocked, bool isLessonCompleted, bool isFullyCompleted) {
    final isExpanded = _expandedLessons[lesson['id']] ?? false;
    final subtopics = lesson['subtopics'] as List;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? lesson['color'] : Colors.grey.shade400),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Lesson Header (Clickable)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLessonUnlocked ? () => _toggleLesson(lesson['id']) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isLessonCompleted ? Colors.green.withOpacity(0.2) : (isLessonUnlocked ? lesson['color'] : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: isLessonCompleted
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 30)
                          : Icon(
                              isLessonUnlocked ? lesson['icon'] : Icons.lock,
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson['title'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${subtopics.length} subtopics',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Poppins-Regular',
                              color: isLessonUnlocked ? Colors.grey[600] : Colors.grey.shade500,
                            ),
                          ),
                          
                          // ============ SHOW EXERCISE AVAILABLE WHEN ALL VIDEOS ARE DONE ============
                          if (isFullyCompleted && !isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.assignment, size: 10, color: Colors.blue.shade700),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Exercise Available',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          if (!isLessonUnlocked)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Complete Fraction first',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Completed',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (isLessonUnlocked)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey[400]!),
                        ),
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.black,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded Subtopics List
          if (isExpanded && isLessonUnlocked)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border(top: BorderSide(color: lesson['color'], width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson['description'],
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  // Progress bar
                  LinearProgressIndicator(
                    value: _getLessonProgress(lesson['title']),
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_getCompletedCount(lesson['title'])}/${subtopics.length} videos completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  
                  const SizedBox(height: 15),
                  
                  ...List.generate(subtopics.length, (index) {
                    final subtopic = subtopics[index];
                    final isVideoUnlocked = _isVideoUnlocked(lesson['title'], index);
                    final isVideoCompleted = progressManager.isSubtopicCompleted(lesson['title'], subtopic['title']);
                    
                    return _buildSubtopicItem(
                      lessonTitle: lesson['title'],
                      subtopic: subtopic,
                      index: index,
                      isUnlocked: isVideoUnlocked,
                      isCompleted: isVideoCompleted,
                    );
                  }),
                  
                  // ============ SHOW EXERCISE BUTTON AT BOTTOM WHEN ALL VIDEOS ARE DONE ============
                  if (isFullyCompleted && !isLessonCompleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _navigateToComprehensiveExercise,
                          child: const Text(
                            'Take Comprehensive Lesson Exercise',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubtopicItem({
    required String lessonTitle,
    required Map<String, dynamic> subtopic,
    required int index,
    required bool isUnlocked,
    required bool isCompleted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnlocked ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCompleted ? Colors.green : (isUnlocked ? Colors.grey[300]! : Colors.grey.shade300),
          width: isCompleted ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? () {
            if (isUnlocked) {
              _navigateToVideo(lessonTitle, subtopic);
            }
          } : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Number indicator
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green.withOpacity(0.2) : (isUnlocked ? const Color(0xFFFFD8A8).withOpacity(0.2) : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFFFD8A8) : Colors.grey.shade400),
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, size: 16, color: Colors.green)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isUnlocked ? Colors.black : Colors.grey.shade600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Video Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subtopic['title'],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 12,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                subtopic['duration'],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!isUnlocked && !isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.orange.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Locked',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Play/Lock button
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFFFF59D) : Colors.grey.shade300),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted ? Colors.green.shade700 : (isUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : (isUnlocked ? Icons.play_arrow : Icons.lock),
                        color: isCompleted ? Colors.white : (isUnlocked ? Colors.black : Colors.grey.shade600),
                        size: 16,
                      ),
                    ),
                  ],
                ),
                
                // Learning Objectives
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (subtopic['learningObjectives'] as List).map((objective) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                objective,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ============ UPDATED DECIMAL VIDEO SCREEN (with lesson completion check) ============
class DecimalVideoScreen extends StatefulWidget {
  final String lessonTitle;
  final String videoTitle;
  final String videoUrl;
  final String? learningObjective;

  const DecimalVideoScreen({
    super.key,
    required this.lessonTitle,
    required this.videoTitle,
    required this.videoUrl,
    this.learningObjective,
  });

  @override
  State<DecimalVideoScreen> createState() => _DecimalVideoScreenState();
}

class _DecimalVideoScreenState extends State<DecimalVideoScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _videoCompleted = false;
  bool _isCheckingCompletion = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset(widget.videoUrl);
      
      await _videoController.initialize();

      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
        _videoCompleted = false;
        _isCheckingCompletion = false;
      });
      
      _videoController.setLooping(false);
      _videoController.play();
      
      _videoController.addListener(() {
        if (_videoController.value.position == _videoController.value.duration && 
            _videoController.value.isPlaying == false) {
          if (!_videoCompleted && !_isCheckingCompletion) {
            setState(() {
              _videoCompleted = true;
            });
            _markAsComplete();
          }
        }
      });
      
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _markAsComplete() async {
    if (_isCheckingCompletion) return;
    
    setState(() {
      _isCheckingCompletion = true;
    });
    
    // Mark video as completed
    progressManager.markVideoCompleted(
      widget.lessonTitle, 
      'English', 
      0, 
      widget.videoTitle
    );
    
    // Mark subtopic as completed
    progressManager.markSubtopicCompleted(
      widget.lessonTitle,
      widget.videoTitle
    );
    
    // Small delay to ensure progress is updated
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Check if lesson is fully completed (both videos done)
    bool isLessonComplete = progressManager.isLessonFullyCompleted(widget.lessonTitle);
    
    setState(() {
      _isCheckingCompletion = false;
    });
    
    if (isLessonComplete && !progressManager.isLessonCompleted(widget.lessonTitle)) {
      // Mark the lesson as completed
      progressManager.markLessonCompleted(widget.lessonTitle);
      
      // Show completion message with exercise option
      _showLessonCompletionDialog();
    } else {
      // Just show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Video marked as complete!',
            style: const TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Go back after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _showLessonCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '🎉 Lesson Complete!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 50),
                    const SizedBox(height: 10),
                    Text(
                      'You completed all videos in',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.lessonTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Would you like to take the comprehensive lesson exercise?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pop(context); // Go back to lessons
              },
              child: const Text(
                'Later',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToComprehensiveExercise();
              },
              child: const Text('Take Exercise'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DecimalExerciseScreen(
        lessonName: widget.lessonTitle,
        language: 'English',
        subLessonIndex: 0,
      )),
    ).then((_) {
      // After exercise, go back to lessons
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  void _changePlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _videoController.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    _videoController.removeListener(() {});
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.lessonTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.videoTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Video Player
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: _isVideoInitialized 
                              ? _videoController.value.aspectRatio 
                              : 16/9,
                          child: _hasError
                              ? _buildErrorWidget()
                              : _isVideoInitialized
                                  ? VideoPlayer(_videoController)
                                  : _buildLoadingWidget(),
                        ),
                        
                        if (_isVideoInitialized && !_hasError)
                          _buildVideoControls(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  
                  // Learning Objective
                  if (widget.learningObjective != null && widget.learningObjective!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.school, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Learning Objective:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                  fontFamily: 'Lora-Regular',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.learningObjective!,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Poppins-Regular',
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                  
                  // MARK AS COMPLETE BUTTON
                  if (!_videoCompleted && _isVideoInitialized && !_hasError)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
                        ),
                        onPressed: _markAsComplete,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Mark as Complete',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Lora-Regular',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // COMPLETED INDICATOR
                  if (_videoCompleted)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 30,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Video Completed!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontFamily: 'Lora-Regular',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.yellow),
            SizedBox(height: 10),
            Text(
              'Loading video...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            const Text(
              'Video not available',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFF59D),
              ),
              onPressed: _initializeVideo,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Speed:', style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, size: 16, color: Colors.white),
                onSelected: _changePlaybackSpeed,
                itemBuilder: (context) => _speedOptions.map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x Speed', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    if (_videoController.value.isPlaying) {
                      _videoController.pause();
                    } else {
                      _videoController.play();
                    }
                  });
                },
              ),
              
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position - const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              
              Text(
                _formatDuration(_videoController.value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              
              Expanded(
                child: VideoProgressIndicator(
                  _videoController,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.yellow,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              
              Text(
                _formatDuration(_videoController.value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position + const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),

              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  _videoController.seekTo(Duration.zero);
                  _videoController.play();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

// ============ UPDATED DECIMAL EXERCISE SCREEN (15 items - Simplified) ============
/// Thin wrapper â€” exercise logic lives in the [exercise_feature.ExerciseScreen] module.
class DecimalExerciseScreen extends StatelessWidget {
  final String lessonName;
  final String language;
  final int subLessonIndex;
  const DecimalExerciseScreen(
      {super.key, required this.lessonName, required this.language, required this.subLessonIndex});
  @override
  Widget build(BuildContext context) {
    final flags = aggregateProgressFlags(
      [lessonName],
      completedCount: progressManager.getCompletedExercisesForLesson,
      hasPassed: progressManager.hasEverPassedExercise,
    );
    final lesson = TopicsData.getLessonByTitle(lessonName);
    final topic = lesson != null
        ? TopicsData.getTopics().firstWhere(
            (t) => t.id == lesson.topicId,
            orElse: () => TopicsData.getTopics().first,
          )
        : null;
    return exercise_feature.ExerciseScreen(
      lessonName: lessonName,
      language: language,
      title: 'Decimal Numbers Exercise',
      questions: DecimalsQuestions.all,
      showAiRemediation: true,
      autoStartRemediation: shouldAutoStartRemediation(
        hasAnyAttempt: flags.hasAnyAttempt,
        hasAnyPass: flags.hasAnyPass,
      ),
      lessonId: lesson?.id ?? lessonName,
      aiLessonContext: buildAiLessonContext(
        lessonTitle: lessonName,
        subtopics: lesson?.subtopics ?? [],
        topicId: lesson?.topicId,
        topicTitle: topic?.title,
      ),
      onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>
          progressManager.recordExerciseScore(lesson, lang, subLessonIndex, type, s, t, c, pct),
      onExerciseInsightsSaved: (names, summary, topics) =>
          progressManager.saveLessonExerciseInsights(
            names,
            summary: summary,
            recommendedSubtopics: topics,
          ),
    );
  }
}

class PercentageLessonsScreen extends StatefulWidget {
  const PercentageLessonsScreen({super.key});

  @override
  State<PercentageLessonsScreen> createState() => _PercentageLessonsScreenState();
}

class _PercentageLessonsScreenState extends State<PercentageLessonsScreen> {
  // Track which lessons are expanded
  final Map<String, bool> _expandedLessons = {
    'percentage': false,
  };

  // Lesson data structure - UPDATED with only 3 subtopics
  final List<Map<String, dynamic>> _lessons = [
    {
      'id': 'percentage',
      'title': 'Percentage',
      'description': 'Learn about percentages - parts per hundred',
      'color': const Color(0xFFA8E3B5), // Green color
      'icon': Icons.percent,
      'subtopics': [
        {
          'title': 'Describing Percentage',
          'learningObjectives': [
            'Describe percentage as "parts per hundred"',
            'Understand that percentage represents a part of a whole',
          ],
          'videoUrl': 'assets/Videos/PercentageDescribing.mp4',
          'duration': '1:10',
        },
        {
          'title': 'Converting Fractions to Percentages',
          'learningObjectives': [
            'Convert 1/4 (25%) to percentage',
            'Convert 1/2 (50%) to percentage',
            'Convert 3/4 (75%) to percentage',
          ],
          'videoUrl': 'assets/Videos/Convertingfractionspercentage.mp4',
          'duration': '2:12',
        },
        {
          'title': 'Converting Percentages to Fractions',
          'learningObjectives': [
            'Convert 25% to fraction form (1/4)',
            'Convert 50% to fraction form (1/2)',
            'Convert 75% to fraction form (3/4)',
          ],
          'videoUrl': 'assets/Videos/Percentagestofractions.mp4',
          'duration': '1:24',
        },
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    // Listen for unlock events
    progressManager.unlockStream.listen((topicName) {
      if (mounted && topicName == 'Percentage') {
        setState(() {});
      }
    });
    // Check if Percentage is unlocked
    _checkIfUnlocked();
  }

  void _checkIfUnlocked() {
    if (!progressManager.isTopicUnlocked('Percentage')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete all lessons in Decimal Numbers first!',
            style: TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  // Check if lesson is unlocked (Percentage only has one lesson)
  bool _isLessonUnlocked(String lessonTitle) {
    return progressManager.isTopicUnlocked('Percentage');
  }

  // Check if ALL videos in a lesson are completed
  bool _isLessonFullyCompleted(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return false;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount == subtopics.length;
    } catch (e) {
      return false;
    }
  }

  // Check if video is unlocked (sequential within lesson)
  bool _isVideoUnlocked(String lessonTitle, int videoIndex) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (videoIndex == 0) {
        return _isLessonUnlocked(lessonTitle);
      }
      
      final previousVideo = subtopics[videoIndex - 1];
      return progressManager.isSubtopicCompleted(lessonTitle, previousVideo['title']);
    } catch (e) {
      return false;
    }
  }

  // Get lesson progress
  double _getLessonProgress(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return 0;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount / subtopics.length;
    } catch (e) {
      return 0;
    }
  }

  // Get completed count
  int _getCompletedCount(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount;
    } catch (e) {
      return 0;
    }
  }

  void _toggleLesson(String lessonId) {
    setState(() {
      _expandedLessons[lessonId] = !(_expandedLessons[lessonId] ?? false);
    });
  }

  void _navigateToVideo(String lessonTitle, Map<String, dynamic> subtopic) {
    // Build learning objectives text
    String learningObjectives = subtopic['learningObjectives'].join('\n• ');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PercentageVideoScreen(
          lessonTitle: lessonTitle,
          videoTitle: subtopic['title'],
          videoUrl: subtopic['videoUrl'],
          learningObjective: 'Learning Objectives:\n• $learningObjectives',
        ),
      ),
    ).then((_) {
      setState(() {});
      
      // Check if Percentage topic is now fully completed
      _checkPercentageCompletion();
    });
  }

  // Navigate to comprehensive exercise
  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PercentageExerciseScreen(
        lessonName: 'Percentage',
        language: 'English',
        subLessonIndex: 0,
      )),
    ).then((_) {
      setState(() {});
    });
  }

  // Check if Percentage topic is fully completed
  void _checkPercentageCompletion() {
    bool percentageCompleted = progressManager.isLessonCompleted('Percentage');
    
    if (percentageCompleted) {
      // Mark Percentage topic as completed
      progressManager.markTopicCompleted('Percentage');
      
      // Unlock next topic (Algebra)
      progressManager.unlockTopic('Algebra');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🔓 Algebra is now unlocked!',
            style: TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUnlocked = progressManager.isTopicUnlocked('Percentage');
    final bool isLessonCompleted = progressManager.isLessonCompleted('Percentage');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Percentage Lessons',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUnlocked 
                    ? const Color(0xFFA8E3B5).withOpacity(0.3) 
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUnlocked ? const Color(0xFFA8E3B5) : Colors.grey.shade400, 
                  width: 2
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Percentage',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                      color: isUnlocked ? Colors.black : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isUnlocked 
                        ? 'Learn about percentages - parts per hundred'
                        : '🔒 Complete all lessons in Decimal Numbers to unlock',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: isUnlocked ? Colors.black54 : Colors.grey.shade600,
                    ),
                  ),
                  if (!isUnlocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, color: Colors.orange.shade700, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'LOCKED',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // Show exercise button when lesson is completed
            if (isLessonCompleted)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.emoji_events, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(
                          'Congratulations!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You completed all Percentage lessons!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _navigateToComprehensiveExercise,
                        child: const Text(
                          'Take Comprehensive Topic Exercise',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Lessons List with Dropdowns
            ..._lessons.map((lesson) {
              final isLessonUnlocked = _isLessonUnlocked(lesson['title']);
              final isLessonCompleted = progressManager.isLessonCompleted(lesson['title']);
              final isFullyCompleted = _isLessonFullyCompleted(lesson['title']);
              
              return _buildDropdownLesson(lesson, isLessonUnlocked, isLessonCompleted, isFullyCompleted);
            }).toList(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownLesson(Map<String, dynamic> lesson, bool isLessonUnlocked, bool isLessonCompleted, bool isFullyCompleted) {
    final isExpanded = _expandedLessons[lesson['id']] ?? false;
    final subtopics = lesson['subtopics'] as List;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? lesson['color'] : Colors.grey.shade400),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Lesson Header (Clickable)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLessonUnlocked ? () => _toggleLesson(lesson['id']) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isLessonCompleted ? Colors.green.withOpacity(0.2) : (isLessonUnlocked ? lesson['color'] : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: isLessonCompleted
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 30)
                          : Icon(
                              isLessonUnlocked ? lesson['icon'] : Icons.lock,
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson['title'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${subtopics.length} subtopics',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Poppins-Regular',
                              color: isLessonUnlocked ? Colors.grey[600] : Colors.grey.shade500,
                            ),
                          ),
                          
                          // Show Exercise Available when all videos are done
                          if (isFullyCompleted && !isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.assignment, size: 10, color: Colors.blue.shade700),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Exercise Available',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          if (!isLessonUnlocked)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Complete Decimal Numbers first',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Completed',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (isLessonUnlocked)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey[400]!),
                        ),
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.black,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded Subtopics List
          if (isExpanded && isLessonUnlocked)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border(top: BorderSide(color: lesson['color'], width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson['description'],
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  // Progress bar
                  LinearProgressIndicator(
                    value: _getLessonProgress(lesson['title']),
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_getCompletedCount(lesson['title'])}/${subtopics.length} videos completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  
                  const SizedBox(height: 15),
                  
                  ...List.generate(subtopics.length, (index) {
                    final subtopic = subtopics[index];
                    final isVideoUnlocked = _isVideoUnlocked(lesson['title'], index);
                    final isVideoCompleted = progressManager.isSubtopicCompleted(lesson['title'], subtopic['title']);
                    
                    return _buildSubtopicItem(
                      lessonTitle: lesson['title'],
                      subtopic: subtopic,
                      index: index,
                      isUnlocked: isVideoUnlocked,
                      isCompleted: isVideoCompleted,
                    );
                  }),
                  
                  // Show exercise button at bottom when all videos are done
                  if (isFullyCompleted && !isLessonCompleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _navigateToComprehensiveExercise,
                          child: const Text(
                            'Take Comprehensive Lesson Exercise',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubtopicItem({
    required String lessonTitle,
    required Map<String, dynamic> subtopic,
    required int index,
    required bool isUnlocked,
    required bool isCompleted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnlocked ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCompleted ? Colors.green : (isUnlocked ? Colors.grey[300]! : Colors.grey.shade300),
          width: isCompleted ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? () {
            if (isUnlocked) {
              _navigateToVideo(lessonTitle, subtopic);
            }
          } : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Number indicator
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green.withOpacity(0.2) : (isUnlocked ? const Color(0xFFA8E3B5).withOpacity(0.2) : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFA8E3B5) : Colors.grey.shade400),
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, size: 16, color: Colors.green)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isUnlocked ? Colors.black : Colors.grey.shade600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Video Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subtopic['title'],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 12,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                subtopic['duration'],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!isUnlocked && !isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.orange.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Locked',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Play/Lock button
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFFFF59D) : Colors.grey.shade300),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted ? Colors.green.shade700 : (isUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : (isUnlocked ? Icons.play_arrow : Icons.lock),
                        color: isCompleted ? Colors.white : (isUnlocked ? Colors.black : Colors.grey.shade600),
                        size: 16,
                      ),
                    ),
                  ],
                ),
                
                // Learning Objectives
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (subtopic['learningObjectives'] as List).map((objective) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                objective,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ UPDATED PERCENTAGE VIDEO SCREEN ============
class PercentageVideoScreen extends StatefulWidget {
  final String lessonTitle;
  final String videoTitle;
  final String videoUrl;
  final String? learningObjective;

  const PercentageVideoScreen({
    super.key,
    required this.lessonTitle,
    required this.videoTitle,
    required this.videoUrl,
    this.learningObjective,
  });

  @override
  State<PercentageVideoScreen> createState() => _PercentageVideoScreenState();
}

class _PercentageVideoScreenState extends State<PercentageVideoScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _videoCompleted = false;
  bool _isCheckingCompletion = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset(widget.videoUrl);
      
      await _videoController.initialize();

      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
        _videoCompleted = false;
        _isCheckingCompletion = false;
      });
      
      _videoController.setLooping(false);
      _videoController.play();
      
      _videoController.addListener(() {
        if (_videoController.value.position == _videoController.value.duration && 
            _videoController.value.isPlaying == false) {
          if (!_videoCompleted && !_isCheckingCompletion) {
            setState(() {
              _videoCompleted = true;
            });
            _markAsComplete();
          }
        }
      });
      
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _markAsComplete() async {
    if (_isCheckingCompletion) return;
    
    setState(() {
      _isCheckingCompletion = true;
    });
    
    // Mark video as completed
    progressManager.markVideoCompleted(
      widget.lessonTitle, 
      'English', 
      0, 
      widget.videoTitle
    );
    
    // Mark subtopic as completed
    progressManager.markSubtopicCompleted(
      widget.lessonTitle,
      widget.videoTitle
    );
    
    // Small delay to ensure progress is updated
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Check if lesson is fully completed (all 3 videos done)
    bool isLessonComplete = _isLessonFullyCompleted(widget.lessonTitle);
    
    setState(() {
      _isCheckingCompletion = false;
    });
    
    if (isLessonComplete && !progressManager.isLessonCompleted(widget.lessonTitle)) {
      // Mark the lesson as completed
      progressManager.markLessonCompleted(widget.lessonTitle);
      
      // Show completion message with exercise option
      _showLessonCompletionDialog();
    } else {
      // Just show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Video marked as complete!',
            style: const TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Go back after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  bool _isLessonFullyCompleted(String lessonName) {
    final videos = VideoDataManager.getVideos(lessonName);
    if (videos.isEmpty) return false;
    
    int completedCount = 0;
    for (var video in videos) {
      if (progressManager.isSubtopicCompleted(lessonName, video['title'])) {
        completedCount++;
      }
    }
    
    return completedCount == videos.length;
  }

  void _showLessonCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '🎉 Lesson Complete!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 50),
                    const SizedBox(height: 10),
                    Text(
                      'You completed all videos in',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.lessonTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Would you like to take the comprehensive lesson exercise?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pop(context); // Go back to lessons
              },
              child: const Text(
                'Later',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToComprehensiveExercise();
              },
              child: const Text('Take Exercise'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PercentageExerciseScreen(
        lessonName: widget.lessonTitle,
        language: 'English',
        subLessonIndex: 0,
      )),
    ).then((_) {
      // After exercise, go back to lessons
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  void _changePlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _videoController.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    _videoController.removeListener(() {});
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.lessonTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.videoTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Video Player
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: _isVideoInitialized 
                              ? _videoController.value.aspectRatio 
                              : 16/9,
                          child: _hasError
                              ? _buildErrorWidget()
                              : _isVideoInitialized
                                  ? VideoPlayer(_videoController)
                                  : _buildLoadingWidget(),
                        ),
                        
                        if (_isVideoInitialized && !_hasError)
                          _buildVideoControls(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  
                  // Learning Objective
                  if (widget.learningObjective != null && widget.learningObjective!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.school, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Learning Objective:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                  fontFamily: 'Lora-Regular',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.learningObjective!,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Poppins-Regular',
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                  
                  // MARK AS COMPLETE BUTTON
                  if (!_videoCompleted && _isVideoInitialized && !_hasError)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
                        ),
                        onPressed: _markAsComplete,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Mark as Complete',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Lora-Regular',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // COMPLETED INDICATOR
                  if (_videoCompleted)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 30,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Video Completed!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontFamily: 'Lora-Regular',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.yellow),
            SizedBox(height: 10),
            Text(
              'Loading video...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            const Text(
              'Video not available',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFF59D),
              ),
              onPressed: _initializeVideo,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Speed:', style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, size: 16, color: Colors.white),
                onSelected: _changePlaybackSpeed,
                itemBuilder: (context) => _speedOptions.map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x Speed', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    if (_videoController.value.isPlaying) {
                      _videoController.pause();
                    } else {
                      _videoController.play();
                    }
                  });
                },
              ),
              
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position - const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              
              Text(
                _formatDuration(_videoController.value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              
              Expanded(
                child: VideoProgressIndicator(
                  _videoController,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.yellow,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              
              Text(
                _formatDuration(_videoController.value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position + const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),

              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  _videoController.seekTo(Duration.zero);
                  _videoController.play();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

// ============ UPDATED PERCENTAGE EXERCISE SCREEN (15 items - Interactive) ============
/// Thin wrapper â€” exercise logic lives in the [exercise_feature.ExerciseScreen] module.
class PercentageExerciseScreen extends StatelessWidget {
  final String lessonName;
  final String language;
  final int subLessonIndex;
  const PercentageExerciseScreen(
      {super.key, required this.lessonName, required this.language, required this.subLessonIndex});
  @override
  Widget build(BuildContext context) {
    final flags = aggregateProgressFlags(
      [lessonName],
      completedCount: progressManager.getCompletedExercisesForLesson,
      hasPassed: progressManager.hasEverPassedExercise,
    );
    final lesson = TopicsData.getLessonByTitle(lessonName);
    final topic = lesson != null
        ? TopicsData.getTopics().firstWhere(
            (t) => t.id == lesson.topicId,
            orElse: () => TopicsData.getTopics().first,
          )
        : null;
    return exercise_feature.ExerciseScreen(
      lessonName: lessonName,
      language: language,
      title: 'Percentage Exercise',
      questions: PercentagesQuestions.all,
      showAiRemediation: true,
      autoStartRemediation: shouldAutoStartRemediation(
        hasAnyAttempt: flags.hasAnyAttempt,
        hasAnyPass: flags.hasAnyPass,
      ),
      lessonId: lesson?.id ?? lessonName,
      aiLessonContext: buildAiLessonContext(
        lessonTitle: lessonName,
        subtopics: lesson?.subtopics ?? [],
        topicId: lesson?.topicId,
        topicTitle: topic?.title,
      ),
      onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>
          progressManager.recordExerciseScore(lesson, lang, subLessonIndex, type, s, t, c, pct),
      onExerciseInsightsSaved: (names, summary, topics) =>
          progressManager.saveLessonExerciseInsights(
            names,
            summary: summary,
            recommendedSubtopics: topics,
          ),
    );
  }
}

class AlgebraLessonsScreen extends StatefulWidget {
  const AlgebraLessonsScreen({super.key});

  @override
  State<AlgebraLessonsScreen> createState() => _AlgebraLessonsScreenState();
}

class _AlgebraLessonsScreenState extends State<AlgebraLessonsScreen> {
  // Track which lessons are expanded
  final Map<String, bool> _expandedLessons = {
    'algebra': false,
  };

  // Lesson data structure - UPDATED with only 4 subtopics (removed Mixed Operations)
  final List<Map<String, dynamic>> _lessons = [
    {
      'id': 'algebra',
      'title': 'Algebra',
      'description': 'Learn to find missing values in mathematical sentences',
      'color': const Color(0xFFD8A8FF), // Lavender color
      'icon': Icons.functions,
      'subtopics': [
        {
          'title': 'Missing Values in Addition',
          'learningObjectives': [
            'Find the missing value to complete addition sentences',
            'Example: 5 + ___ = 12',
            'Example: ___ + 8 = 15',
          ],
          'videoUrl': 'assets/Videos/AlgebAdd.mp4',
          'duration': '1:36',
        },
        {
          'title': 'Missing Values in Subtraction',
          'learningObjectives': [
            'Find the missing value to complete subtraction sentences',
            'Example: 15 - ___ = 7',
            'Example: ___ - 9 = 6',
          ],
          'videoUrl': 'assets/Videos/AlgebSub.mp4',
          'duration': '1:28',
        },
        {
          'title': 'Missing Values in Multiplication',
          'learningObjectives': [
            'Find the missing value to complete multiplication sentences',
            'Example: 6 × ___ = 42',
            'Example: ___ × 8 = 56',
          ],
          'videoUrl': 'assets/Videos/AlgebMulti.mp4',
          'duration': '1:27',
        },
        {
          'title': 'Missing Values in Division',
          'learningObjectives': [
            'Find the missing value to complete division sentences',
            'Example: 24 ÷ ___ = 6',
            'Example: ___ ÷ 5 = 9',
          ],
          'videoUrl': 'assets/Videos/AlgebDiv.mp4',
          'duration': '1:35',
        },
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    // Listen for unlock events
    progressManager.unlockStream.listen((topicName) {
      if (mounted && topicName == 'Algebra') {
        setState(() {});
      }
    });
    // Check if Algebra is unlocked
    _checkIfUnlocked();
  }

  void _checkIfUnlocked() {
    if (!progressManager.isTopicUnlocked('Algebra')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete all lessons in Percentage first!',
            style: TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  // Check if lesson is unlocked (Algebra only has one lesson)
  bool _isLessonUnlocked(String lessonTitle) {
    return progressManager.isTopicUnlocked('Algebra');
  }

  // ============ IMPORTANT: Check if ALL videos in a lesson are completed ============
  bool _isLessonFullyCompleted(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return false;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      // Lesson is fully completed if ALL subtopics are completed
      return completedCount == subtopics.length;
    } catch (e) {
      return false;
    }
  }

  // Check if video is unlocked (sequential within lesson)
  bool _isVideoUnlocked(String lessonTitle, int videoIndex) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (videoIndex == 0) {
        return _isLessonUnlocked(lessonTitle);
      }
      
      final previousVideo = subtopics[videoIndex - 1];
      return progressManager.isSubtopicCompleted(lessonTitle, previousVideo['title']);
    } catch (e) {
      return false;
    }
  }

  // Get lesson progress
  double _getLessonProgress(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      if (subtopics.isEmpty) return 0;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount / subtopics.length;
    } catch (e) {
      return 0;
    }
  }

  // Get completed count
  int _getCompletedCount(String lessonTitle) {
    try {
      final lesson = _lessons.firstWhere(
        (lesson) => lesson['title'] == lessonTitle,
      );
      final subtopics = lesson['subtopics'] as List;
      
      int completedCount = 0;
      for (var subtopic in subtopics) {
        if (progressManager.isSubtopicCompleted(lessonTitle, subtopic['title'])) {
          completedCount++;
        }
      }
      
      return completedCount;
    } catch (e) {
      return 0;
    }
  }

  void _toggleLesson(String lessonId) {
    setState(() {
      _expandedLessons[lessonId] = !(_expandedLessons[lessonId] ?? false);
    });
  }

  void _navigateToVideo(String lessonTitle, Map<String, dynamic> subtopic) {
    // Build learning objectives text
    String learningObjectives = subtopic['learningObjectives'].join('\n• ');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlgebraVideoScreen(
          lessonTitle: lessonTitle,
          videoTitle: subtopic['title'],
          videoUrl: subtopic['videoUrl'],
          learningObjective: 'Learning Objectives:\n• $learningObjectives',
        ),
      ),
    ).then((_) {
      setState(() {});
      
      // Check if Algebra topic is now fully completed
      _checkAlgebraCompletion();
    });
  }

  // Navigate to comprehensive exercise
  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AlgebraExerciseScreen(
        lessonName: 'Algebra',
        language: 'English',
        subLessonIndex: 0,
      )),
    ).then((_) {
      setState(() {});
    });
  }

  // Check if Algebra topic is fully completed
  void _checkAlgebraCompletion() {
    bool algebraCompleted = progressManager.isLessonCompleted('Algebra');
    
    if (algebraCompleted) {
      // Mark Algebra topic as completed
      progressManager.markTopicCompleted('Algebra');
      
      // All topics completed! Show congratulations message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎉 Congratulations! You completed all topics! 🎉',
            style: TextStyle(fontFamily: 'Poppins-Regular', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.purple,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUnlocked = progressManager.isTopicUnlocked('Algebra');
    final bool isLessonCompleted = progressManager.isLessonCompleted('Algebra');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Algebra',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUnlocked 
                    ? const Color(0xFFD8A8FF).withOpacity(0.3) 
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUnlocked ? const Color(0xFFD8A8FF) : Colors.grey.shade400, 
                  width: 2
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Algebra',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                      color: isUnlocked ? Colors.black : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isUnlocked 
                        ? 'Find missing values in mathematical sentences'
                        : '🔒 Complete all lessons in Percentage to unlock',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: isUnlocked ? Colors.black54 : Colors.grey.shade600,
                    ),
                  ),
                  if (!isUnlocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, color: Colors.orange.shade700, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'LOCKED',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // ============ FIXED: Show exercise button only when lesson is completed ============
            if (isLessonCompleted)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.emoji_events, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(
                          'Congratulations!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You completed all Algebra lessons!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _navigateToComprehensiveExercise,
                        child: const Text(
                          'Take Comprehensive Topic Exercise',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Lessons List with Dropdowns
            ..._lessons.map((lesson) {
              final isLessonUnlocked = _isLessonUnlocked(lesson['title']);
              final isLessonCompleted = progressManager.isLessonCompleted(lesson['title']);
              final isFullyCompleted = _isLessonFullyCompleted(lesson['title']);
              
              return _buildDropdownLesson(lesson, isLessonUnlocked, isLessonCompleted, isFullyCompleted);
            }).toList(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownLesson(Map<String, dynamic> lesson, bool isLessonUnlocked, bool isLessonCompleted, bool isFullyCompleted) {
    final isExpanded = _expandedLessons[lesson['id']] ?? false;
    final subtopics = lesson['subtopics'] as List;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? lesson['color'] : Colors.grey.shade400),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Lesson Header (Clickable)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLessonUnlocked ? () => _toggleLesson(lesson['id']) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isLessonCompleted ? Colors.green.withOpacity(0.2) : (isLessonUnlocked ? lesson['color'] : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLessonCompleted ? Colors.green : (isLessonUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: isLessonCompleted
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 30)
                          : Icon(
                              isLessonUnlocked ? lesson['icon'] : Icons.lock,
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson['title'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isLessonUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${subtopics.length} subtopics',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Poppins-Regular',
                              color: isLessonUnlocked ? Colors.grey[600] : Colors.grey.shade500,
                            ),
                          ),
                          
                          // ============ FIXED: Show Exercise Available when ALL videos are done ============
                          if (isFullyCompleted && !isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.assignment, size: 10, color: Colors.blue.shade700),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Exercise Available',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          if (!isLessonUnlocked)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Complete Percentage first',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isLessonCompleted)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Completed',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (isLessonUnlocked)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey[400]!),
                        ),
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.black,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded Subtopics List
          if (isExpanded && isLessonUnlocked)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border(top: BorderSide(color: lesson['color'], width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson['description'],
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins-Regular',
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  // Progress bar
                  LinearProgressIndicator(
                    value: _getLessonProgress(lesson['title']),
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_getCompletedCount(lesson['title'])}/${subtopics.length} videos completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  
                  const SizedBox(height: 15),
                  
                  ...List.generate(subtopics.length, (index) {
                    final subtopic = subtopics[index];
                    final isVideoUnlocked = _isVideoUnlocked(lesson['title'], index);
                    final isVideoCompleted = progressManager.isSubtopicCompleted(lesson['title'], subtopic['title']);
                    
                    return _buildSubtopicItem(
                      lessonTitle: lesson['title'],
                      subtopic: subtopic,
                      index: index,
                      isUnlocked: isVideoUnlocked,
                      isCompleted: isVideoCompleted,
                    );
                  }),
                  
                  // ============ FIXED: Show exercise button at bottom when ALL videos are done ============
                  if (isFullyCompleted && !isLessonCompleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _navigateToComprehensiveExercise,
                          child: const Text(
                            'Take Comprehensive Lesson Exercise',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubtopicItem({
    required String lessonTitle,
    required Map<String, dynamic> subtopic,
    required int index,
    required bool isUnlocked,
    required bool isCompleted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnlocked ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCompleted ? Colors.green : (isUnlocked ? Colors.grey[300]! : Colors.grey.shade300),
          width: isCompleted ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? () {
            if (isUnlocked) {
              _navigateToVideo(lessonTitle, subtopic);
            }
          } : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Number indicator
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green.withOpacity(0.2) : (isUnlocked ? const Color(0xFFD8A8FF).withOpacity(0.2) : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFD8A8FF) : Colors.grey.shade400),
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, size: 16, color: Colors.green)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isUnlocked ? Colors.black : Colors.grey.shade600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Video Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subtopic['title'],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Lora-Regular',
                              color: isUnlocked ? Colors.black : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 12,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                subtopic['duration'],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!isUnlocked && !isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.orange.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Locked',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, size: 10, color: Colors.green.shade700),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Play/Lock button
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green : (isUnlocked ? const Color(0xFFFFF59D) : Colors.grey.shade300),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted ? Colors.green.shade700 : (isUnlocked ? Colors.black : Colors.grey.shade400),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : (isUnlocked ? Icons.play_arrow : Icons.lock),
                        color: isCompleted ? Colors.white : (isUnlocked ? Colors.black : Colors.grey.shade600),
                        size: 16,
                      ),
                    ),
                  ],
                ),
                
                // Learning Objectives
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (subtopic['learningObjectives'] as List).map((objective) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.purple.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                objective,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Poppins-Regular',
                                  color: Colors.purple.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ UPDATED ALGEBRA VIDEO SCREEN (with lesson completion check) ============
class AlgebraVideoScreen extends StatefulWidget {
  final String lessonTitle;
  final String videoTitle;
  final String videoUrl;
  final String? learningObjective;

  const AlgebraVideoScreen({
    super.key,
    required this.lessonTitle,
    required this.videoTitle,
    required this.videoUrl,
    this.learningObjective,
  });

  @override
  State<AlgebraVideoScreen> createState() => _AlgebraVideoScreenState();
}

class _AlgebraVideoScreenState extends State<AlgebraVideoScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _videoCompleted = false;
  bool _isCheckingCompletion = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset(widget.videoUrl);
      
      await _videoController.initialize();

      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
        _videoCompleted = false;
        _isCheckingCompletion = false;
      });
      
      _videoController.setLooping(false);
      _videoController.play();
      
      _videoController.addListener(() {
        if (_videoController.value.position == _videoController.value.duration && 
            _videoController.value.isPlaying == false) {
          if (!_videoCompleted && !_isCheckingCompletion) {
            setState(() {
              _videoCompleted = true;
            });
            _markAsComplete();
          }
        }
      });
      
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _markAsComplete() async {
    if (_isCheckingCompletion) return;
    
    setState(() {
      _isCheckingCompletion = true;
    });
    
    // Mark video as completed
    progressManager.markVideoCompleted(
      widget.lessonTitle, 
      'English', 
      0, 
      widget.videoTitle
    );
    
    // Mark subtopic as completed
    progressManager.markSubtopicCompleted(
      widget.lessonTitle,
      widget.videoTitle
    );
    
    // Small delay to ensure progress is updated
    await Future.delayed(const Duration(milliseconds: 300));
    
    // ============ IMPORTANT: Check if ALL videos in the lesson are completed ============
    bool isLessonComplete = _isLessonFullyCompleted(widget.lessonTitle);
    
    setState(() {
      _isCheckingCompletion = false;
    });
    
    if (isLessonComplete && !progressManager.isLessonCompleted(widget.lessonTitle)) {
      // Mark the lesson as completed
      progressManager.markLessonCompleted(widget.lessonTitle);
      
      // Show completion message with exercise option
      _showLessonCompletionDialog();
    } else {
      // Just show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Video marked as complete!',
            style: const TextStyle(fontFamily: 'Poppins-Regular'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Go back after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  // ============ Helper method to check if ALL videos are completed ============
  bool _isLessonFullyCompleted(String lessonName) {
    final videos = VideoDataManager.getVideos(lessonName);
    if (videos.isEmpty) return false;
    
    int completedCount = 0;
    for (var video in videos) {
      if (progressManager.isSubtopicCompleted(lessonName, video['title'])) {
        completedCount++;
      }
    }
    
    return completedCount == videos.length;
  }

  void _showLessonCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '🎉 Lesson Complete!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 50),
                    const SizedBox(height: 10),
                    Text(
                      'You completed all videos in',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.lessonTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Would you like to take the comprehensive lesson exercise?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pop(context); // Go back to lessons
              },
              child: const Text(
                'Later',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToComprehensiveExercise();
              },
              child: const Text('Take Exercise'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToComprehensiveExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AlgebraExerciseScreen(
        lessonName: widget.lessonTitle,
        language: 'English',
        subLessonIndex: 0,
      )),
    ).then((_) {
      // After exercise, go back to lessons
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  void _changePlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _videoController.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    _videoController.removeListener(() {});
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.lessonTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.videoTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora-Regular',
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Video Player
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: _isVideoInitialized 
                              ? _videoController.value.aspectRatio 
                              : 16/9,
                          child: _hasError
                              ? _buildErrorWidget()
                              : _isVideoInitialized
                                  ? VideoPlayer(_videoController)
                                  : _buildLoadingWidget(),
                        ),
                        
                        if (_isVideoInitialized && !_hasError)
                          _buildVideoControls(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  
                  // Learning Objective
                  if (widget.learningObjective != null && widget.learningObjective!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.school, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Learning Objective:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                  fontFamily: 'Lora-Regular',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.learningObjective!,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Poppins-Regular',
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                  
                  // MARK AS COMPLETE BUTTON
                  if (!_videoCompleted && _isVideoInitialized && !_hasError)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
                        ),
                        onPressed: _markAsComplete,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Mark as Complete',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Lora-Regular',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // COMPLETED INDICATOR
                  if (_videoCompleted)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 30,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Video Completed!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontFamily: 'Lora-Regular',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.yellow),
            SizedBox(height: 10),
            Text(
              'Loading video...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            const Text(
              'Video not available',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFF59D),
              ),
              onPressed: _initializeVideo,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Speed:', style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, size: 16, color: Colors.white),
                onSelected: _changePlaybackSpeed,
                itemBuilder: (context) => _speedOptions.map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x Speed', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    if (_videoController.value.isPlaying) {
                      _videoController.pause();
                    } else {
                      _videoController.play();
                    }
                  });
                },
              ),
              
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position - const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),
              
              Text(
                _formatDuration(_videoController.value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              
              Expanded(
                child: VideoProgressIndicator(
                  _videoController,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.yellow,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              
              Text(
                _formatDuration(_videoController.value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  final newPosition = _videoController.value.position + const Duration(seconds: 10);
                  _videoController.seekTo(newPosition);
                },
              ),

              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  _videoController.seekTo(Duration.zero);
                  _videoController.play();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

// ============ UPDATED ALGEBRA EXERCISE SCREEN (15 items - Interactive) ============
/// Thin wrapper â€” exercise logic lives in the [exercise_feature.ExerciseScreen] module.
class AlgebraExerciseScreen extends StatelessWidget {
  final String lessonName;
  final String language;
  final int subLessonIndex;
  const AlgebraExerciseScreen(
      {super.key, required this.lessonName, required this.language, required this.subLessonIndex});
  @override
  Widget build(BuildContext context) {
    final flags = aggregateProgressFlags(
      [lessonName],
      completedCount: progressManager.getCompletedExercisesForLesson,
      hasPassed: progressManager.hasEverPassedExercise,
    );
    final lesson = TopicsData.getLessonByTitle(lessonName);
    final topic = lesson != null
        ? TopicsData.getTopics().firstWhere(
            (t) => t.id == lesson.topicId,
            orElse: () => TopicsData.getTopics().first,
          )
        : null;
    return exercise_feature.ExerciseScreen(
      lessonName: lessonName,
      language: language,
      title: 'Algebra Exercise',
      questions: AlgebraQuestions.all,
      showAiRemediation: true,
      autoStartRemediation: shouldAutoStartRemediation(
        hasAnyAttempt: flags.hasAnyAttempt,
        hasAnyPass: flags.hasAnyPass,
      ),
      lessonId: lesson?.id ?? lessonName,
      aiLessonContext: buildAiLessonContext(
        lessonTitle: lessonName,
        subtopics: lesson?.subtopics ?? [],
        topicId: lesson?.topicId,
        topicTitle: topic?.title,
      ),
      onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>
          progressManager.recordExerciseScore(lesson, lang, subLessonIndex, type, s, t, c, pct),
      onExerciseInsightsSaved: (names, summary, topics) =>
          progressManager.saveLessonExerciseInsights(
            names,
            summary: summary,
            recommendedSubtopics: topics,
          ),
    );
  }
}

class StudentProgressScreen extends StatefulWidget {
  const StudentProgressScreen({Key? key}) : super(key: key);

  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> {
  // ── Expansion state ─────────────────────────────────────
  final Map<String, bool> _expandedTopics  = {};
  final Map<String, bool> _expandedLessons = {};

  String searchTerm  = '';
  String filterType  = 'all';

  // ── Color palette ────────────────────────────────────────
  final Color dashboardYellow = const Color(0xFFFEDA5F);
  final Color topicsBlue      = const Color(0xFFA8D5E3);
  final Color topicsPink      = const Color(0xFFF5C6D6);
  final Color topicsPurple    = const Color(0xFFC4B1E1);
  final Color topicsOrange    = const Color(0xFFFFD8A8);
  final Color topicsGreen     = const Color(0xFFA8E3B5);
  final Color topicsLavender  = const Color(0xFFD8A8FF);

  // ── Cached data — computed once, never in build() ────────
  List<Lesson>                         _allLessons  = [];
  Map<String, Map<String, dynamic>>    _lessonCache = {};
  Map<String, Map<String, dynamic>>    _topicCache  = {};
  Map<String, dynamic>                 _summaryCache = {};
  bool _isLoading = true;

  // ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    progressManager.initialize();
    // Cache the lesson list once — avoids repeated getAllLessons() calls
    _allLessons = TopicsData.getAllLessons();
    // Compute heavy data off the current frame
    Future.microtask(_refreshData);
  }

  // ── Compute all data and store in caches ─────────────────
  void _refreshData() {
    if (!mounted) return;

    final newLessonCache = <String, Map<String, dynamic>>{};
    for (final lesson in _allLessons) {
      newLessonCache[lesson.id] = _computeLessonProgress(lesson.id);
    }

    final newTopicCache = <String, Map<String, dynamic>>{};
    for (final topic in TopicsData.getTopics()) {
      newTopicCache[topic.id] = _computeTopicProgress(topic.id, newLessonCache);
    }

    final newSummary = _computeSummary(newLessonCache);

    if (mounted) {
      setState(() {
        _lessonCache  = newLessonCache;
        _topicCache   = newTopicCache;
        _summaryCache = newSummary;
        _isLoading    = false;
      });
    }
  }

  // ── Compute one lesson's progress ────────────────────────
  Map<String, dynamic> _computeLessonProgress(String lessonId) {
    final lesson = TopicsData.getLessonById(lessonId);
    if (lesson == null) return {};

    final lessonName         = lesson.title;
    final progressData       = progressManager.getLessonProgress(lessonName);
    final videoCount         = VideoDataManager.getVideoCount(lessonName);
    final exerciseScores     = progressManager.getExerciseScoresByLesson(lessonName);
    final completedSubtopics = progressManager.getCompletedSubtopicsForLesson(lessonName);
    final subtopics          = lesson.subtopics;

    final Map<String, Map<String, dynamic>> subtopicProgress = {};
    for (final subtopic in subtopics) {
      final isCompleted = completedSubtopics.contains(subtopic);

      final subtopicScores = exerciseScores
          .where((e) => (e['exercise_type'] as String)
              .toLowerCase()
              .contains(subtopic.toLowerCase()))
          .toList();

      double avgScore = 0;
      if (subtopicScores.isNotEmpty) {
        avgScore = subtopicScores.fold(
                0.0, (sum, s) => sum + (s['percentage'] as double)) /
            subtopicScores.length;
      }

      subtopicProgress[subtopic] = {
        'completed':          isCompleted,
        'video_completed':    isCompleted,
        'exercise_completed': subtopicScores.isNotEmpty,
        'score':              avgScore > 0 ? avgScore : null,
        'percentage':         avgScore,
        'attempts':           subtopicScores.length,
        'status': isCompleted
            ? 'Completed'
            : (subtopicScores.isNotEmpty ? 'Exercises Done' : 'Not Started'),
        'scores':     subtopicScores,
        'last_score': subtopicScores.isNotEmpty
            ? '${subtopicScores.last['score']}/${subtopicScores.last['total_questions']}'
            : null,
      };
    }

    return {
      'id':                     lesson.id,
      'title':                  lesson.title,
      'topicId':                lesson.topicId,
      'subtopics':              subtopics,
      'subtopicCount':          subtopics.length,
      'completedSubtopicCount': completedSubtopics.length,
      'subtopicProgress':       subtopicProgress,
      'hasAssessment':          (progressData['exercises_completed'] as int) > 0,
      'progress':               progressData['progress'],
      'average_score':          progressData['average_score'],
      'videos_completed':       progressData['videos_completed'],
      'exercises_completed':    progressData['exercises_completed'],
      'completed_subtopics':    completedSubtopics,
      'videoCount':             videoCount,
      'exerciseCount':          progressData['exerciseCount'],
      'best_score':             progressData['best_score'],
      'total_attempts':         progressData['total_attempts'],
      'exerciseScores':         exerciseScores,
      'exerciseInsights':
          progressManager.getLessonExerciseInsights(lessonName),
    };
  }

  // ── Compute one topic's progress ─────────────────────────
  Map<String, dynamic> _computeTopicProgress(
      String topicId,
      Map<String, Map<String, dynamic>> lessonCache) {
    final topic = TopicsData.getTopics().firstWhere((t) => t.id == topicId);

    double totalProgress      = 0;
    int    completedLessons   = 0;
    int    totalVideos        = 0;
    int    totalExercises     = 0;
    int    completedVideos    = 0;
    int    completedExercises = 0;
    double totalScore         = 0;
    int    scoreCount         = 0;
    int    totalSubtopics     = 0;
    int    completedSubtopics = 0;

    for (final lesson in topic.lessons) {
      final pd = lessonCache[lesson.id] ?? {};
      if (pd.isEmpty) continue;

      final progress = pd['progress'] as double;
      totalProgress += progress;

      totalVideos        += pd['videoCount']          as int;
      totalExercises     += pd['exerciseCount']        as int;
      completedVideos    += pd['videos_completed']     as int;
      completedExercises += pd['exercises_completed']  as int;

      final subtopics = pd['subtopics']         as List<String>;
      final subProg   = pd['subtopicProgress']  as Map<String, Map<String, dynamic>>;
      totalSubtopics += subtopics.length;
      for (final sub in subtopics) {
        if (subProg[sub]?['video_completed'] == true) completedSubtopics++;
      }

      if (progress >= 90) completedLessons++;

      final avg = pd['average_score'] as double;
      if (avg > 0) { totalScore += avg; scoreCount++; }
    }

    return {
      'topicId':            topicId,
      'topicTitle':         topic.title,
      'totalLessons':       topic.lessons.length,
      'completedLessons':   completedLessons,
      'averageProgress':    topic.lessons.isNotEmpty
          ? totalProgress / topic.lessons.length
          : 0.0,
      'averageScore':       scoreCount > 0 ? totalScore / scoreCount : 0.0,
      'inProgress':         topic.lessons.length - completedLessons,
      'totalVideos':        totalVideos,
      'totalExercises':     totalExercises,
      'completedVideos':    completedVideos,
      'completedExercises': completedExercises,
      'totalSubtopics':     totalSubtopics,
      'completedSubtopics': completedSubtopics,
    };
  }

  // ── Compute overall summary ──────────────────────────────
  Map<String, dynamic> _computeSummary(
      Map<String, Map<String, dynamic>> lessonCache) {
    int    completedLessons        = 0;
    double totalProgress           = 0;
    int    totalVideosWatched      = 0;
    int    totalExercisesCompleted = 0;
    int    totalSubtopics          = 0;
    int    completedSubtopics      = 0;
    int    inProgressLessons       = 0;

    for (final lesson in _allLessons) {
      final pd = lessonCache[lesson.id] ?? {};
      if (pd.isEmpty) continue;

      final progress = pd['progress'] as double;
      totalProgress += progress;
      if (progress >= 90) completedLessons++;
      if (progress > 0 && progress < 90) inProgressLessons++;

      totalVideosWatched      += pd['videos_completed']    as int;
      totalExercisesCompleted += pd['exercises_completed'] as int;

      final subtopics = pd['subtopics']        as List<String>;
      final subProg   = pd['subtopicProgress'] as Map<String, Map<String, dynamic>>;
      totalSubtopics += subtopics.length;
      for (final sub in subtopics) {
        if (subProg[sub]?['video_completed'] == true) completedSubtopics++;
      }
    }

    final overallStats           = progressManager.getOverallStats();
    final totalCorrectAnswers    = overallStats['correct_answers']          as int;
    final totalQuestionsAnswered = overallStats['total_questions_answered'] as int;
    final totalVideos            = VideoDataManager.getTotalVideos();
    final accuracyRate = totalQuestionsAnswered > 0
        ? (totalCorrectAnswers / totalQuestionsAnswered * 100).round()
        : 0;

    return {
      'totalLessons':       _allLessons.length,
      'completedLessons':   completedLessons,
      'avgProgress':        _allLessons.isNotEmpty
          ? (totalProgress / _allLessons.length).toInt()
          : 0,
      'inProgress':         inProgressLessons,
      'notStarted':         _allLessons.length - completedLessons - inProgressLessons,
      'completionRate':     _allLessons.isNotEmpty
          ? (completedLessons / _allLessons.length * 100).toInt()
          : 0,
      'videosWatched':      totalVideosWatched,
      'exercisesCompleted': totalExercisesCompleted,
      'totalVideos':        totalVideos,
      'totalExercises':     _allLessons.length,
      'totalSubtopics':     totalSubtopics,
      'completedSubtopics': completedSubtopics,
      'accuracyRate':       accuracyRate,
    };
  }

  // ── Safe cached accessors ────────────────────────────────
  Map<String, dynamic> _lessonProgress(String lessonId) =>
      _lessonCache[lessonId] ?? {};
  Map<String, dynamic> _topicProgress(String topicId) =>
      _topicCache[topicId] ?? {};

  // ── Color helpers ────────────────────────────────────────
  Color getTopicColor(String t) {
    if (t.contains('Number Values'))          return topicsBlue;
    if (t.contains('Fundamental Operations')) return topicsPink;
    if (t.contains('Fraction'))               return topicsPurple;
    if (t.contains('Decimal Numbers'))        return topicsOrange;
    if (t.contains('Percentage'))             return topicsGreen;
    if (t.contains('Algebra'))                return topicsLavender;
    return dashboardYellow;
  }

  Color getLessonColor(String l) {
    switch (l) {
      case 'Whole Numbers':   return topicsBlue;
      case 'Comparison':      return topicsPink;
      case 'Addition':        return topicsBlue;
      case 'Subtraction':     return topicsPink;
      case 'Multiplication':  return topicsPurple;
      case 'Division':        return topicsGreen;
      case 'Fraction':        return topicsPurple;
      case 'Decimal Numbers': return topicsOrange;
      case 'Percentage':      return topicsGreen;
      case 'Algebra':         return topicsLavender;
      default:                return dashboardYellow;
    }
  }

  Color getProgressColor(double p) {
    if (p >= 90) return Colors.green;
    if (p >= 75) return Colors.orange;
    if (p >= 50) return dashboardYellow;
    if (p >   0) return Colors.blue;
    return Colors.grey;
  }

  Color getScoreColor(double s) {
    if (s >= 90) return Colors.green;
    if (s >= 75) return Colors.orange;
    if (s >= 60) return dashboardYellow;
    if (s >   0) return Colors.red;
    return Colors.grey;
  }

  void toggleTopic(String id) =>
      setState(() => _expandedTopics[id]  = !(_expandedTopics[id]  ?? false));
  void toggleLesson(String id) =>
      setState(() => _expandedLessons[id] = !(_expandedLessons[id] ?? false));

  // ── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: dashboardYellow,
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              const Text(
                'Loading progress...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: dashboardYellow.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: dashboardYellow, width: 1),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Progress',
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                        Text(
                          'Track your learning journey',
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  // Refresh button
                  GestureDetector(
                    onTap: () {
                      setState(() => _isLoading = true);
                      Future.microtask(_refreshData);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Icon(Icons.refresh, color: Colors.black, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // ── Summary stat cards ───────────────────────────
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildStatCard(
                    icon: Icons.menu_book,
                    title: 'Lessons',
                    value:
                        '${_summaryCache['completedLessons']}/${_summaryCache['totalLessons']}',
                    subtitle: '${_summaryCache['completionRate']}% done',
                    color: topicsBlue,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Icons.play_circle,
                    title: 'Videos',
                    value:
                        '${_summaryCache['videosWatched']}/${_summaryCache['totalVideos']}',
                    subtitle:
                        '${(_summaryCache['totalVideos'] as int) > 0 ? ((_summaryCache['videosWatched'] as int) / (_summaryCache['totalVideos'] as int) * 100).toInt() : 0}%',
                    color: topicsPink,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Icons.assignment,
                    title: 'Exercises',
                    value:
                        '${_summaryCache['exercisesCompleted']}/${_summaryCache['totalExercises']}',
                    subtitle: '${_summaryCache['accuracyRate']}% accuracy',
                    color: topicsPurple,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Icons.list,
                    title: 'Subtopics',
                    value:
                        '${_summaryCache['completedSubtopics']}/${_summaryCache['totalSubtopics']}',
                    subtitle:
                        '${(_summaryCache['totalSubtopics'] as int) > 0 ? ((_summaryCache['completedSubtopics'] as int) / (_summaryCache['totalSubtopics'] as int) * 100).toInt() : 0}%',
                    color: topicsGreen,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Search + filter ──────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(Icons.search, color: Colors.grey.shade600, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search lessons...',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: Colors.grey.shade500),
                            ),
                            onChanged: (v) => setState(() => searchTerm = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All',         filterType == 'all'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Completed',   filterType == 'completed'),
                        const SizedBox(width: 8),
                        _buildFilterChip('In Progress', filterType == 'in-progress'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Not Started', filterType == 'not-started'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Topics list ──────────────────────────────────
            Expanded(child: _buildTopicsList()),
          ],
        ),
      ),
    );
  }

  // ── Stat card widget ─────────────────────────────────────
  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.black, size: 24),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87)),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }

  // ── Filter chip widget ───────────────────────────────────
  Widget _buildFilterChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () =>
          setState(() => filterType = label.toLowerCase().replaceAll(' ', '-')),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? dashboardYellow : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? dashboardYellow : Colors.grey.shade300,
              width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.black : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // ── Topics list builder ──────────────────────────────────
  Widget _buildTopicsList() {
    final allTopics = TopicsData.getTopics();
    final filtered  = <Map<String, dynamic>>[];

    for (final topic in allTopics) {
      final filteredLessons = topic.lessons.where((lesson) {
        final pd       = _lessonProgress(lesson.id);
        final progress = (pd['progress'] as double?) ?? 0.0;

        final matchesSearch = searchTerm.isEmpty ||
            lesson.title.toLowerCase().contains(searchTerm.toLowerCase()) ||
            topic.title.toLowerCase().contains(searchTerm.toLowerCase());

        final matchesFilter = filterType == 'all' ||
            (filterType == 'completed'   && progress >= 90) ||
            (filterType == 'in-progress' && progress > 0 && progress < 90) ||
            (filterType == 'not-started' && progress == 0);

        return matchesSearch && matchesFilter;
      }).toList();

      if (filteredLessons.isNotEmpty) {
        filtered.add({'topic': topic, 'lessons': filteredLessons});
      }
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: dashboardYellow.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: dashboardYellow, width: 2),
              ),
              child: Icon(Icons.search_off, size: 50, color: dashboardYellow),
            ),
            const SizedBox(height: 16),
            Text('No lessons match your filters',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final topic      = filtered[index]['topic']   as Topic;
        final lessons    = filtered[index]['lessons'] as List<Lesson>;
        final tp         = _topicProgress(topic.id);
        final topicColor = getTopicColor(topic.title);

        return Column(
          children: [
            _buildTopicHeader(topic, tp, topicColor),
            if (_expandedTopics[topic.id] ?? false)
              ...lessons.map(_buildLessonCard).toList(),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  // ── Topic header ─────────────────────────────────────────
  Widget _buildTopicHeader(
      Topic topic, Map<String, dynamic> tp, Color topicColor) {
    final progress = (tp['averageProgress'] as double?) ?? 0.0;

    return GestureDetector(
      onTap: () => toggleTopic(topic.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: topicColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            // Number badge
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Center(
                child: Text(
                  topic.title.split(' ')[0],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 15),

            // Title + sub-info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${topic.lessons.length} lessons • '
                    '${(tp['completedVideos'] ?? 0)}/${(tp['totalVideos'] ?? 0)} videos',
                    style: TextStyle(
                        fontSize: 12, color: Colors.black.withOpacity(0.7)),
                  ),
                ],
              ),
            ),

            // Progress circle + chevron
            Row(
              children: [
                SizedBox(
                  width: 45,
                  height: 45,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.5),
                          border: progress == 0
                              ? Border.all(color: Colors.grey.shade400, width: 1)
                              : null,
                        ),
                      ),
                      if (progress > 0)
                        CircularProgressIndicator(
                          value: progress / 100,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              getProgressColor(progress)),
                          strokeWidth: 4,
                        ),
                      Center(
                        child: Text(
                          '${progress.toInt()}%',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  (_expandedTopics[topic.id] ?? false)
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.black,
                  size: 24,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Lesson card ──────────────────────────────────────────
  Widget _buildLessonCard(Lesson lesson) {
    final pd           = _lessonProgress(lesson.id);
    final progress     = (pd['progress']      as double?) ?? 0.0;
    final avgScore     = (pd['average_score'] as double?) ?? 0.0;
    final subtopics    = (pd['subtopics']     as List<String>?) ?? [];
    final subCount     = (pd['subtopicCount'] as int?)    ?? 0;
    final compSubCount = (pd['completedSubtopicCount'] as int?) ?? 0;
    final subProg      = (pd['subtopicProgress']
            as Map<String, Map<String, dynamic>>?) ??
        {};
    final exScores     =
        (pd['exerciseScores'] as List<Map<String, dynamic>>?) ?? [];
    final isExpanded   = _expandedLessons[lesson.id] ?? false;
    final lessonColor  = getLessonColor(lesson.title);

    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Lesson header row
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: lessonColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: lessonColor, width: 1),
              ),
              child: Center(
                child: Text(
                  '${progress.toInt()}%',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            title: Text(lesson.title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    _tag(
                        '${pd['videos_completed'] ?? 0}/${pd['videoCount'] ?? 0} videos',
                        topicsBlue),
                    const SizedBox(width: 4),
                    _tag(
                        '${pd['exercises_completed'] ?? 0}/${pd['exerciseCount'] ?? 0} exercises',
                        topicsGreen),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$compSubCount/$subCount subtopics completed',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            trailing: IconButton(
              icon: Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 20,
                color: Colors.black,
              ),
              onPressed: () => toggleLesson(lesson.id),
            ),
          ),

          // Expanded detail section
          if (isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),

                  // Subtopics header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Subtopics ($compSubCount/$subCount)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: lessonColor),
                      ),
                      if (avgScore > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                getScoreColor(avgScore).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: getScoreColor(avgScore)),
                          ),
                          child: Text(
                            '${avgScore.toInt()}% avg',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: getScoreColor(avgScore)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Subtopic rows
                  ...subtopics.map((sub) => _buildSubtopicItem(
                        sub,
                        subProg[sub] ??
                            {
                              'completed': false,
                              'video_completed': false,
                              'exercise_completed': false,
                              'score': null,
                              'percentage': 0.0,
                              'attempts': 0,
                              'status': 'Not Started',
                              'scores': <Map<String, dynamic>>[],
                              'last_score': null,
                            },
                        lessonColor,
                      )),

                  // AI recap (last successful exercise summary)
                  if (pd['exerciseInsights'] != null) ...[
                    const SizedBox(height: 16),
                    _buildLessonInsightsSection(
                      Map<String, dynamic>.from(
                        pd['exerciseInsights']! as Map,
                      ),
                      lessonColor,
                    ),
                  ],

                  // Recent exercise scores
                  if (exScores.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        'Recent Attempts',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...exScores.take(3).map(_buildScoreItem),
                  ],

                  // Best score badge
                  if ((pd['best_score'] as double? ?? 0) > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: dashboardYellow.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: dashboardYellow),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(Icons.emoji_events,
                                color: dashboardYellow, size: 18),
                            const SizedBox(width: 8),
                            const Text('Best Score',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: dashboardYellow)),
                            child: Text(
                              '${(pd['best_score'] as double).toInt()}%',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
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

  // ── Small tag pill ───────────────────────────────────────
  Widget _tag(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.black)),
      );

  // ── Subtopic row ─────────────────────────────────────────
  Widget _buildSubtopicItem(String subtopic,
      Map<String, dynamic> progress, Color lessonColor) {
    final bool videoCompleted    = progress['video_completed']    == true;
    final bool exerciseCompleted = progress['exercise_completed'] == true;
    final double score    = (progress['score'] as double?) ?? 0.0;
    final int    attempts = (progress['attempts'] as int?)  ?? 0;
    final String? lastScore = progress['last_score'] as String?;

    String statusText  = 'Not Started';
    Color  statusColor = Colors.grey;
    if (videoCompleted)    { statusText = 'Completed';      statusColor = Colors.green; }
    else if (exerciseCompleted) { statusText = 'Exercises Done'; statusColor = Colors.blue; }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: videoCompleted
                  ? Colors.green
                  : (exerciseCompleted ? Colors.blue : Colors.grey.shade300),
              border: Border.all(
                  color: videoCompleted
                      ? Colors.green
                      : (exerciseCompleted
                          ? Colors.blue
                          : Colors.grey.shade500),
                  width: 2),
            ),
            child: (videoCompleted || exerciseCompleted)
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 8),

          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtopic,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: (videoCompleted || exerciseCompleted)
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: (videoCompleted || exerciseCompleted)
                          ? Colors.black
                          : Colors.grey.shade600),
                ),
                Text(statusText,
                    style: TextStyle(
                        fontSize: 9,
                        color: statusColor,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),

          // Score tags
          if (videoCompleted || exerciseCompleted) ...[
            if (lastScore != null && lastScore.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade300)),
                child: Text(lastScore,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700)),
              ),
              const SizedBox(width: 4),
            ],
            if (score > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: getScoreColor(score).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: getScoreColor(score))),
                child: Text('${score.toInt()}%',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: getScoreColor(score))),
              ),
          ] else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade400)),
              child: Text('Not started',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade600)),
            ),

          // Attempts count
          if (attempts > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purple.shade300)),
              child: Text('$attempts',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade700)),
            ),
          ],
        ],
      ),
    );
  }

  // ── AI exercise recap (My Progress) ───────────────────────
  Widget _buildLessonInsightsSection(
    Map<String, dynamic> insights,
    Color lessonColor,
  ) {
    final summary = insights['summary'] as String? ?? '';
    final topicsRaw = insights['recommended_subtopics'];
    final topics = <String>[];
    if (topicsRaw is List) {
      for (final e in topicsRaw) {
        final t = e?.toString().trim();
        if (t != null && t.isNotEmpty) topics.add(t);
      }
    }
    final savedAt = insights['saved_at'] as String?;
    DateTime? savedParsed;
    if (savedAt != null && savedAt.isNotEmpty) {
      try {
        savedParsed = DateTime.parse(savedAt);
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 14, color: lessonColor),
              const SizedBox(width: 6),
              Text(
                'Insights',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary.isNotEmpty)
                Text(
                  summary,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              if (topics.isNotEmpty) ...[
                if (summary.isNotEmpty) const SizedBox(height: 8),
                Text(
                  'Suggested review',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: lessonColor,
                  ),
                ),
                const SizedBox(height: 4),
                ...topics.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ',
                            style: TextStyle(fontSize: 12, color: lessonColor)),
                        Expanded(
                          child: Text(t, style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (savedParsed != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 10, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(savedParsed),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Exercise score row ───────────────────────────────────
  Widget _buildScoreItem(Map<String, dynamic> score) {
    final int    scoreValue    = score['score']           as int;
    final int    totalQ        = score['total_questions'] as int;
    final double percentage    = score['percentage']      as double;
    final String exerciseType  = score['exercise_type']   as String;
    final DateTime completedAt =
        DateTime.parse(score['completed_at'] as String);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: getScoreColor(percentage).withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: getScoreColor(percentage), width: 2),
            ),
            child: Center(
              child: Text('$scoreValue',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: getScoreColor(percentage))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exerciseType,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.calendar_today,
                      size: 10, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(_formatDate(completedAt),
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  Text('${percentage.toInt()}%',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: getScoreColor(percentage))),
                ]),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade400)),
            child: Text('$scoreValue/$totalQ',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7)  return '$diff days ago';
    return '${date.month}/${date.day}';
  }
}

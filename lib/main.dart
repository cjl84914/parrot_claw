import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/local_gateway_repository.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/data/service/impl/openclaw_service_factory.dart';
import 'package:parrot_app/data/service/local_gateway_service.dart';
import 'package:parrot_app/data/service/openclaw_installer_service.dart';
import 'package:parrot_app/data/service/openclaw_model_service.dart';
import 'package:parrot_app/data/service/shared_preferences_service.dart';
import 'package:parrot_app/data/service/storage_service.dart';
import 'package:parrot_app/ui/screen/chat_screen.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';
import 'package:parrot_app/ui/screen/setup_screen.dart';
import 'package:parrot_app/ui/screen/setup_model_screen.dart';
import 'package:parrot_app/ui/screen/more_screen.dart';
import 'package:parrot_app/ui/screen/model_list_screen.dart';
import 'package:parrot_app/ui/screen/webview_screen.dart';
import 'package:parrot_app/ui/screen/server_edit_screen.dart';
import 'package:parrot_app/ui/screen/server_list_screen.dart';
import 'package:parrot_app/ui/screen/qr_code_screen.dart';
import 'package:parrot_app/ui/screen/qr_scan_screen.dart';
import 'package:parrot_app/ui/screen/setting_screen.dart';
import 'package:parrot_app/ui/screen/voice_screen.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:parrot_app/ui/view_model/setup_viewmodel.dart';
import 'package:parrot_app/ui/view_model/setup_model_viewmodel.dart';
import 'package:parrot_app/ui/view_model/setting_viewmodel.dart';
import 'package:parrot_app/util/asr_util.dart';
import 'package:parrot_app/util/flutter_tts_util.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'ui/screen/live2d_screen.dart';
import 'ui/view_model/server_viewmodel.dart';

void main() async {
  Logger.root.level = kDebugMode ? Level.ALL : Level.OFF;

  WidgetsFlutterBinding.ensureInitialized();
  // await dotenv.load(fileName: '.env');
  // to store the database in.
  final storageService = StorageService();
  await storageService.init();

  final prefs = await SharedPreferences.getInstance();
  await FlutterTTSUtil().initSetting();
  await ASRUtil().init();

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    // Must add this line.
    await windowManager.ensureInitialized();
    // Windows 使用系统标题栏（原生支持拖动/最小化/关闭）；
    // macOS 保持隐藏标题栏的无边框体验（其标题栏区域本身可拖动）。
    const WindowOptions windowOptions = WindowOptions(
      size: Size(390, 844),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    runApp(
      MultiProvider(
        providers: providersLocal(prefs, storageService),
        child: const MyApp(),
      ),
    );
  } else {
    runApp(
      MultiProvider(
        providers: providersLocal(prefs, storageService),
        child: const MyApp(),
      ),
    );
  }
}

List<SingleChildWidget> providersLocal(
  SharedPreferences prefs,
  StorageService storageService,
) {
  final openClawServices = OpenClawServiceFactory.create();

  return [
    Provider.value(value: storageService),
    Provider(create: (context) => SharedPreferencesService(prefs)),
    ChangeNotifierProvider(
      create:
          (context) => SettingRepository(preferencesService: context.read()),
    ),
    ChangeNotifierProvider(
      create: (context) => ServerRepository(context.read<StorageService>()),
    ),
    // 本地网关：Service + Repository（依赖 ServerRepository）
    Provider<LocalGatewayService>.value(value: openClawServices.gateway),
    Provider<OpenClawInstallerService>.value(value: openClawServices.installer),
    Provider<OpenClawModelService>.value(value: openClawServices.model),
    ChangeNotifierProvider(
      create:
          (context) => LocalGatewayRepository(
            service: context.read(),
            installerService: context.read(),
            serverRepository: context.read(),
          ),
    ),
    ChangeNotifierProvider(
      create: (context) => SettingViewmodel(settingRepository: context.read()),
    ),
    ChangeNotifierProvider(
      create: (context) => ServerViewModel(serverRepository: context.read()),
    ),
    ChangeNotifierProvider(
      create:
          (context) => ConnViewModel(
            settingRepository: context.read(),
            serverRepository: context.read(),
          ),
    ),
    // 本地引导 ViewModel
    ChangeNotifierProvider(
      create:
          (context) => SetupViewModel(
            repository: context.read(),
            modelService: context.read(),
          ),
    ),
    ChangeNotifierProvider(
      create:
          (context) => SetupModelViewModel(serverRepository: context.read()),
    ),
  ];
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      // Use builder only if you need to use library outside ScreenUtilInit context
      builder: (_, child) {
        return MaterialApp.router(
          title: '语鹦助手',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: ThemeMode.dark,
          builder: (context, widget) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.0.sp)),
              child: FlutterEasyLoading(child: widget),
            );
          },
          routerConfig: router,
        );
      },
    );
  }
}

final GoRouter router = GoRouter(
  initialLocation: Routes.home,
  debugLogDiagnostics: true,
  routes: <RouteBase>[
    GoRoute(
      path: Routes.home,
      redirect: (context, state) {
        final serverRepository = context.read<ServerRepository>();
        if (serverRepository.servers.isEmpty) {
          // 无服务器时：桌面系统先进本地引导界面，移动端维持原逻辑
          if (Platform.isMacOS || Platform.isWindows
          // || Platform.isLinux
          ) {
            return Routes.setup;
          }
          return Routes.serverEdit;
        } else {
          return Routes.index;
        }
      },
    ),
    ShellRoute(
      builder: (context, state, child) {
        final serverRepository = context.watch<ServerRepository>();
        final selectedServer = serverRepository.selectedServer;
        if (selectedServer == null) {
          return SetupScreen(viewModel: context.read());
        }
        return IndexScreen(
          key: ValueKey(selectedServer.id),
          viewModel: context.read(),
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: Routes.index,
          pageBuilder: (context, state) {
            final serverRepository = context.watch<ServerRepository>();
            final selectedServer = serverRepository.selectedServer;
            return NoTransitionPage(
              child: ChatScreen(
                key: ValueKey(selectedServer?.id ?? 'no-selected-server'),
                viewModel: context.read(),
              ),
            );
          },
        ),
        GoRoute(
          path: Routes.voice,
          pageBuilder:
              (context, state) => NoTransitionPage(
                child: VoiceScreen(viewModel: context.read()),
              ),
        ),
        GoRoute(
          path: Routes.about,
          pageBuilder:
              (context, state) => NoTransitionPage(
                child: SettingScreen(viewmodel: context.read()),
              ),
        ),
      ],
    ),
    GoRoute(
      path: Routes.setup,
      builder: (context, state) {
        return SetupScreen(viewModel: context.read());
      },
    ),
    GoRoute(
      path: Routes.modelList,
      builder: (context, state) {
        return ModelListScreen(service: context.read());
      },
    ),
    GoRoute(
      path: Routes.setupModel,
      builder: (context, state) {
        return SetupModelScreen(viewModel: context.read());
      },
    ),
    GoRoute(
      path: Routes.serverEdit,
      builder: (context, state) {
        if (state.extra != null) {
          return ServerEditScreen(
            viewModel: context.read(),
            server: state.extra as ServerConfig,
          );
        } else {
          return ServerEditScreen(viewModel: context.read());
        }
      },
    ),
    GoRoute(
      path: Routes.serverList,
      builder: (context, state) {
        return ServerListScreen(viewModel: context.read());
      },
    ),
    GoRoute(
      path: Routes.qrScan,
      builder: (context, state) {
        return QrScanScreen(viewModel: context.read());
      },
    ),
    GoRoute(
      path: Routes.qrCode,
      builder: (context, state) {
        return QrCodeScreen(config: state.extra as ServerConfig);
      },
    ),
    GoRoute(
      path: Routes.live2d,
      builder: (context, state) {
        return const Live2dScreen();
      },
    ),
    GoRoute(
      path: Routes.more,
      builder: (context, state) {
        return const MoreScreen();
      },
    ),
    GoRoute(
      path: '/webview',
      builder: (context, state) {
        final params = state.uri.queryParameters;
        return WebViewScreen(
          title: params['title'] ?? '',
          assetPath: params['assetPath'] ?? '',
        );
      },
    ),
  ],
);

abstract final class Routes {
  static const home = '/';
  static const index = '/index';
  static const login = '/login';
  static const chat = '/chat';
  static const serverList = '/server_list';
  static const serverEdit = '/server_edit';
  static const qrScan = '/qr_scan';
  static const qrCode = '/qr_code';
  static const about = '/about';
  static const live2d = '/live2d';
  static const more = '/more';
  static const webview = '/webview';
  static const setup = '/setup';
  static const setupModel = '/setup_model';
  static const modelList = '/model_list';
  static const voice = '/voice';
  static const setting = '/setting';
}

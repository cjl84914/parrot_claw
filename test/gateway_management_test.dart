import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/ui/view_model/cron_viewmodel.dart';
import 'package:parrot_app/ui/view_model/skill_viewmodel.dart';

import 'support/fake_gateway_session.dart';

/// Skill / Cron 管理的状态机回归测试。
///
/// 这两条链路现在完全跑在 `GatewayRepository` 上（它直接持有网关会话），
/// ViewModel 只是转发。测试的接缝因此落在「假会话」上：按方法名给响应，
/// 顺带能断言请求有没有真的发出去。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SkillViewModel 加载数据并拒绝重叠操作', () async {
    final built = await buildConnectedRepository();
    built.session.handler = (method, params) {
      if (method == 'skills.status') {
        return {
          'skills': [
            {'skillKey': 'weather', 'name': 'Weather'},
          ],
        };
      }
      return const <String, dynamic>{};
    };
    final viewModel = SkillViewModel(gatewayRepository: built.repository);

    final first = viewModel.load();
    final second = viewModel.load();
    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(viewModel.skills.single.key, 'weather');
    expect(viewModel.isLoading, isFalse);

    built.session.fail = true;
    expect(await viewModel.install(name: 'weather', installId: 'brew'), isFalse);
    expect(viewModel.error, contains('skills.install failed'));

    // 等 fire-and-forget 的初始化请求落地，否则它们回调时会撞上「仓库已释放」。
    await pumpEventQueue();
    built.repository.dispose();
  });

  // test('CronViewModel 加载并运行任务，状态稳定', () async {
  //   final built = await buildConnectedRepository();
  //   built.session.handler = (method, params) {
  //     if (method == 'cron.list') {
  //       return {
  //         'jobs': [
  //           {'id': 'job-1', 'name': 'Daily'},
  //         ],
  //       };
  //     }
  //     return null;
  //   };
  //   final viewModel = CronViewModel(gatewayRepository: built.repository);
  //
  //   expect(await viewModel.load(), isTrue);
  //   expect(viewModel.jobs.single.id, 'job-1');
  //   expect(await viewModel.run('job-1'), isTrue);
  //   expect(viewModel.lastOperation, 'run');
  //
  //   built.session.fail = true;
  //   expect(await viewModel.load(), isFalse);
  //   expect(viewModel.error, contains('cron.list failed'));
  //
  //   built.repository.dispose();
  // });

  test('打网关之前先做本地校验，校验不过就不发请求', () async {
    final built = await buildConnectedRepository();
    // connect() 期间仓库会自己拉会话 / 模型 / 历史，先把这些噪声清掉。
    // 它们都是 fire-and-forget，所以要先等它们真的落地再清。
    await pumpEventQueue();
    built.session.requests.clear();

    final skill = SkillViewModel(gatewayRepository: built.repository);
    expect(await skill.install(name: ' ', installId: 'brew'), isFalse);
    expect(skill.error, contains('Skill 名称不能为空'));
    expect(await skill.install(name: 'weather', installId: ' '), isFalse);
    expect(skill.error, contains('安装方式不能为空'));

    final cron = CronViewModel(gatewayRepository: built.repository);
    expect(await cron.add(const <String, dynamic>{}), isFalse);
    expect(cron.error, contains('任务参数不能为空'));
    expect(await cron.update('job-1', const <String, dynamic>{}), isFalse);
    expect(cron.error, contains('更新内容不能为空'));
    expect(await cron.run('  '), isFalse);
    expect(cron.error, contains('任务 ID 不能为空'));

    expect(built.session.requests, isEmpty, reason: '本地校验没过就不该打到网关');

    built.repository.dispose();
  });

  test('仓库 dispose 会关掉自己持有的会话', () async {
    final built = await buildConnectedRepository();
    await pumpEventQueue();
    expect(built.session.shutDown, isFalse);

    built.repository.dispose();
    await Future<void>.delayed(Duration.zero);

    // 仓库是会话的所有者：不真的关掉的话，会话的退避重连会留着一个
    // 已经没人消费的连接继续重试。
    expect(built.session.shutDown, isTrue);
  });
}

// 小小电脑的单元测试。
//
// 原来的 widget_test.dart 是 Flutter 模板自带的“计数器”测试，本项目里根本没有
// 那个控件，所以它永远失败。这里换成真正针对本仓库业务逻辑的测试——重点是那些
// 曾经出过 bug、或者一旦改错就会静默损坏用户数据的地方。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_computer/l10n/app_localizations.dart';
import 'package:tiny_computer/workflow.dart';

void main() {
  // Util.validateBetween 通过 AppLocalizations.of(G.homePageStateContext) 取文案，
  // 所以需要先把一个带 Localizations 的真实 BuildContext 塞进 G。
  // 用 testWidgets 起一棵最小 widget 树来拿这个 context。
  testWidgets('准备带本地化的 BuildContext', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: Builder(
        builder: (context) {
          G.homePageStateContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    expect(G.homePageStateContext, isNotNull);
  });

  group('Util.validateBetween', () {
    test('空值与非法输入应被拒绝', () {
      expect(Util.validateBetween(null, 0, 100, () {}), isNotNull);
      expect(Util.validateBetween('', 0, 100, () {}), isNotNull);
      expect(Util.validateBetween('abc', 0, 100, () {}), isNotNull);
      // int.tryParse('1.5') == null，视为非法
      expect(Util.validateBetween('1.5', 0, 100, () {}), isNotNull);
    });

    test('越界值应被拒绝', () {
      expect(Util.validateBetween('-1', 0, 100, () {}), isNotNull);
      expect(Util.validateBetween('101', 0, 100, () {}), isNotNull);
    });

    test('合法值应被接受并回调', () {
      var called = false;
      expect(Util.validateBetween('50', 0, 100, () => called = true), isNull);
      expect(called, isTrue);
      // 边界值
      expect(Util.validateBetween('0', 0, 100, () {}), isNull);
      expect(Util.validateBetween('100', 0, 100, () {}), isNull);
    });
  });

  group('默认值表 D', () {
    test('快捷指令的键必须完整（缺 name/command 会让按钮点了没反应）', () {
      for (final cmd in D.commands) {
        final name = cmd['name'];
        final command = cmd['command'];
        expect(name, isNotNull, reason: '存在缺少 name 的指令');
        expect(command, isNotNull, reason: '存在缺少 command 的指令');
        expect(name!.isNotEmpty, isTrue);
        expect(command!.isNotEmpty, isTrue);
      }
    });

    test('Wine 指令同样必须有 name 与 command', () {
      for (final cmd in D.wineCommands) {
        expect(cmd['name'], isNotNull);
        expect(cmd['command'], isNotNull);
      }
    });

    test('终端小键盘每一项都要有 name 和 key', () {
      for (final key in D.termCommands) {
        expect(key['name'], isNotNull);
        expect(key['key'], isNotNull);
      }
    });

    test('启动命令必须包含 proot 且挂载 rootfs', () {
      // D.boot 是容器的启动命令，一旦写坏容器就起不来
      expect(D.boot, contains('proot'));
      expect(D.boot, contains('--rootfs='));
      expect(D.boot, contains('--link2symlink'));
    });
  });

  group('分片命名约束', () {
    // App 端在容器安装脚本里用 `cat xa*` 拼接 rootfs 分片（lib/workflow.dart），
    // shell 的通配符按字典序展开，所以分片名必须满足“字典序 == 拆分顺序”。
    // 这里把这条约束固化成测试，避免以后有人改分片命名时踩坑。
    String splitName(int index) {
      // 与 build.ps1 / build.sh / prepare-inputs.sh 的规则一致：
      // GNU split 默认前缀 + 两位字母后缀，26 片以内是 xaa..xaz
      if (index < 26) {
        return 'xa${String.fromCharCode(97 + index)}';
      }
      final n = index - 26;
      final hi = (n ~/ 26) + 1;
      final lo = n % 26;
      return 'xa${hi.toString().padLeft(2, '0')}${String.fromCharCode(97 + lo)}';
    }

    test('26 片以内命名必须是 xaa..xaz（兼容已发布 assets）', () {
      final names = List.generate(26, splitName);
      expect(names.first, 'xaa');
      expect(names.last, 'xaz');
      expect(names.toSet().length, 26, reason: '分片名必须唯一');
    });

    test('26 片以内字典序必须等于拆分顺序（cat xa* 依赖这一点）', () {
      final names = List.generate(26, splitName);
      final sorted = [...names]..sort();
      expect(sorted, equals(names));
    });

    test('分片名长度固定为 3（便于 shell glob 与正则统一匹配）', () {
      for (var i = 0; i < 26; i++) {
        expect(splitName(i).length, 3);
      }
    });
  });
}

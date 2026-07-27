package com.geetion.parrot;

import android.os.Bundle;
import androidx.annotation.Nullable;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import com.baidu.mobstat.StatService;

public class MainActivity extends FlutterActivity {
    private static final String DUIX_DOWNLOAD_CHANNEL = "duix_download_service";

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // 调试模式下，打开log开关，可以看到调试log
        StatService.setDebugOn(false);
        // 设置app发布渠道
        StatService.setAppChannel(this, "官方", true);
        String versionName = "unknown";
        try {
            PackageInfo packageInfo = getPackageManager().getPackageInfo(getPackageName(), 0);
            versionName = packageInfo.versionName;
        } catch (PackageManager.NameNotFoundException e) {
            throw new RuntimeException(e);
        }
        StatService.setAppVersionName(this, versionName);
        // 设置Appkey
        StatService.setAppKey("b6ac64942a");
        // 启动sdk
        StatService.start(this);
    }

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
    }
}
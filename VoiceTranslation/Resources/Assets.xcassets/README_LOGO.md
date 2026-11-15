# Logo 资源设置说明

## 📍 Logo 位置
您的 logo 图标需要放在以下文件夹中：
```
VoiceTranslation/Resources/Assets.xcassets/AppIcon.appiconset/
```

## 📐 需要的图片格式和尺寸

**格式：PNG（推荐）**
**背景：透明或白色**

需要以下尺寸的图片文件：

| 文件名 | 尺寸 | 用途 |
|--------|------|------|
| `icon_16x16.png` | 16×16 | 小图标 |
| `icon_16x16@2x.png` | 32×32 | 小图标高分辨率 |
| `icon_32x32.png` | 32×32 | 中小图标 |
| `icon_32x32@2x.png` | 64×64 | 中小图标高分辨率 |
| `icon_128x128.png` | 128×128 | 中等图标 |
| `icon_128x128@2x.png` | 256×256 | 中等图标高分辨率 |
| `icon_256x256.png` | 256×256 | 大图标 |
| `icon_256x256@2x.png` | 512×512 | 大图标高分辨率 |
| `icon_512x512.png` | 512×512 | 超大图标 |
| `icon_512x512@2x.png` | 1024×1024 | 超大图标高分辨率 |

## 🎨 设计要求

1. **圆角矩形**：macOS Big Sur 风格，圆角半径约为尺寸的 22%
2. **清晰可辨**：即使在 16×16 尺寸也能清楚看出图标内容
3. **无文字**：避免在小尺寸图标中使用文字
4. **简洁设计**：符合 macOS 设计原则

## 🛠️ 生成工具推荐

### 在线生成工具：
- **AppIcon Generator**: https://appicon.co/
- **Icon Slate**: 专业的图标生成工具
- **Sketch** 或 **Figma**: 设计软件

### 自动生成步骤：
1. 创建一个 1024×1024 的主图标
2. 使用在线工具自动生成所有尺寸
3. 下载生成的文件包
4. 将文件复制到上述文件夹中

## 📝 添加到 Xcode 项目

1. 打开 `VoiceTranslation.xcodeproj`
2. 在项目导航器中找到 `Resources` 文件夹
3. 右键点击 → "Add Files to VoiceTranslation"
4. 选择 `Assets.xcassets` 文件夹
5. 确认添加到项目中

## ✅ 验证图标

添加后可以：
1. 在 Xcode 中构建应用
2. 在 Finder 中查看应用包图标
3. 在 Dock 中查看应用图标

## 🎯 快速开始

如果您已经有了一个主图标文件：
1. 访问 https://appicon.co/
2. 上传您的 1024×1024 图标
3. 选择 "macOS" 平台
4. 下载生成的文件
5. 将文件复制到 `AppIcon.appiconset/` 文件夹中

完成后您的应用就会显示自定义图标了！
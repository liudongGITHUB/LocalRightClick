# 应用图标

使用内置 imagegen 生成 `AppIcon.png`，用 macOS `sips` 转换为 16、32、128、256、512 点及对应双倍分辨率的 PNG，再用 `iconutil` 打包为 `AppIcon.icns`。构建脚本将 ICNS 复制进应用资源目录。

生成提示词：

Use case: logo-brand. Create a single polished macOS application icon for a lightweight Finder right-click utility called 轻右键. Square 1024x1024 asset. A beautifully proportioned rounded-square blue to indigo tile, centered with modest transparent exterior margins, native macOS utility aesthetic. Center a clean sculpted white computer mouse silhouette with a clearly highlighted cyan right mouse button and a very small subtle click accent. Strong recognizable silhouette legible at 32px. Front/top view, balanced geometric proportions, restrained soft lighting and dimensional depth, smooth edges. No text, letters, watermark, extra objects, or presentation mockup. Actual transparent background outside the rounded square tile. Deliver only the finished icon.

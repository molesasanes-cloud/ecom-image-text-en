# 电商图片英文排版 Skill

将电商详情页、主图和 SKU 图片中的中文文案翻译成英文，在 Codex 中使用内置图片编辑和本地 PowerShell 脚本完成排版。

## 适用范围

- 从图片读取中文并拟定英文文案；统一一套图片的术语与字号层级。
- 用真实字体绘制英文，避免生成式文字变形。
- 在平滑背景上局部补底，并检查接缝、残字及文字框外的像素变化。
- 保留原始图片尺寸；原图与英文版分开保存。

复杂纹理、人物或商品被旧字覆盖时，无法保证自动还原被遮挡的细节。`SKILL.md` 要求将有可见瑕疵的图片标为未完成，交给设计师复核。

## 安装到 Codex（Windows）

1. 在 GitHub 仓库页面选择 **Code → Download ZIP**。
2. 解压后，将包含 `SKILL.md` 的文件夹复制到 `%USERPROFILE%\.codex\skills\ecom-image-text-en`。最终路径应为 `%USERPROFILE%\.codex\skills\ecom-image-text-en\SKILL.md`。
3. 重新打开 Codex，在任务中写 `$ecom-image-text-en` 并附上要处理的图片或图片文件夹。

示例请求：

> 使用 `$ecom-image-text-en` 把这套详情图中的中文翻译成英文。保持人物、商品、场景和原图尺寸，只修改文案。先做一张样张让我确认。

此 Skill 使用 Codex 内置图片编辑能力，不需要单独的图像 API Key。当前内置工具不一定提供底层模型选择，不能保证指定 GPT Image 2。局部合成脚本使用 Windows PowerShell 和 `System.Drawing`；在 macOS 或 Linux 上需要改写脚本。

## 仓库文件

- `SKILL.md`：工作流程、验收规则和提示词。
- `scripts/typeset-english.ps1`：擦除简单背景文字并用真实字体排版英文。
- `scripts/lock-text-regions.ps1`：将核对过的局部编辑合成回原图尺寸，保留区域外像素。

使用前请检查脚本和输入图片。不要把 API 密钥或私人图片提交到仓库。

## 许可

本仓库代码与说明以 [MIT License](LICENSE) 开源。


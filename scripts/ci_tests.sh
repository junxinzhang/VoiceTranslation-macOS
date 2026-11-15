#!/bin/bash

# 持续集成环境下的测试脚本
# 适用于GitHub Actions, Jenkins等CI环境
# 创建时间: 2025-08-11

set -e  # 遇到错误时立即退出
set -o pipefail  # 管道命令中任何一个失败都会导致整个管道失败

# 环境变量配置
PROJECT_NAME="VoiceTranslation"
SCHEME_NAME="VoiceTranslation"
WORKSPACE_PATH="../${PROJECT_NAME}.xcodeproj"
DESTINATION="platform=macOS"

# 创建必要的目录
mkdir -p TestResults
mkdir -p Reports

echo "========================================"
echo "      CI 环境自动化测试"
echo "========================================"
echo "时间: $(date)"
echo "项目: $PROJECT_NAME"
echo "========================================"

# 检查环境
echo "🔧 检查测试环境..."

# 检查Xcode版本
XCODE_VERSION=$(xcodebuild -version | head -n 1 || echo "Unknown")
echo "Xcode版本: $XCODE_VERSION"

# 检查macOS版本
MACOS_VERSION=$(sw_vers -productVersion)
echo "macOS版本: $MACOS_VERSION"

# 检查Swift版本
SWIFT_VERSION=$(swift --version | head -n 1 || echo "Unknown")
echo "Swift版本: $SWIFT_VERSION"

echo ""

# 清理环境
echo "🧹 清理构建环境..."
xcodebuild clean -project "$WORKSPACE_PATH" -scheme "$SCHEME_NAME" > /dev/null

# 构建项目
echo "🔨 构建项目..."
xcodebuild build \
    -project "$WORKSPACE_PATH" \
    -scheme "$SCHEME_NAME" \
    -destination "$DESTINATION" \
    -configuration Debug \
    -quiet || {
    echo "❌ 项目构建失败"
    exit 1
}

echo "✅ 项目构建成功"

# 运行测试
echo "🧪 运行测试套件..."
TEST_START_TIME=$(date +%s)

xcodebuild test \
    -project "$WORKSPACE_PATH" \
    -scheme "$SCHEME_NAME" \
    -destination "$DESTINATION" \
    -configuration Debug \
    -enableCodeCoverage YES \
    -resultBundlePath "./TestResults/CITestResults.xcresult" \
    -quiet || {
    
    echo "❌ 测试执行失败"
    
    # 生成详细的失败报告
    echo "📋 生成详细测试报告..."
    xcodebuild test \
        -project "$WORKSPACE_PATH" \
        -scheme "$SCHEME_NAME" \
        -destination "$DESTINATION" \
        -configuration Debug \
        -enableCodeCoverage YES \
        -resultBundlePath "./TestResults/FailedTestResults.xcresult"
    
    # 导出测试日志
    if [ -d "./TestResults/FailedTestResults.xcresult" ]; then
        xcrun xcresulttool get --format json \
            --path "./TestResults/FailedTestResults.xcresult" \
            > "./Reports/test_failures.json" 2>/dev/null || echo "无法生成失败报告"
    fi
    
    exit 1
}

TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

echo "✅ 测试执行完成 (${TEST_DURATION}s)"

# 生成测试报告
echo "📊 生成测试报告..."

# 生成JSON格式的测试结果
if [ -d "./TestResults/CITestResults.xcresult" ]; then
    xcrun xcresulttool get --format json \
        --path "./TestResults/CITestResults.xcresult" \
        > "./Reports/test_results.json" 2>/dev/null || echo "警告: 无法生成测试结果JSON"
fi

# 生成覆盖率报告
echo "📈 生成代码覆盖率报告..."

if [ -d "./TestResults/CITestResults.xcresult" ]; then
    # JSON格式覆盖率报告
    xcrun xccov view --report --json \
        "./TestResults/CITestResults.xcresult" \
        > "./Reports/coverage_report.json" 2>/dev/null || echo "警告: 无法生成覆盖率JSON"
    
    # 文本格式覆盖率报告
    xcrun xccov view --report \
        "./TestResults/CITestResults.xcresult" \
        > "./Reports/coverage_report.txt" 2>/dev/null || echo "警告: 无法生成覆盖率文本报告"
fi

# 解析测试结果
echo "🔍 分析测试结果..."

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
COVERAGE_PERCENTAGE="N/A"

if [ -f "./Reports/test_results.json" ]; then
    # 使用Python解析测试结果
    python3 -c "
import json
import sys

try:
    with open('./Reports/test_results.json', 'r') as f:
        data = json.load(f)
    
    # 这里需要根据实际的xcresult JSON结构来解析
    # 简化版本的结果提取
    print('解析测试结果完成')
except Exception as e:
    print(f'警告: 无法解析测试结果: {e}')
" 2>/dev/null
fi

if [ -f "./Reports/coverage_report.json" ]; then
    # 提取覆盖率百分比
    COVERAGE_PERCENTAGE=$(python3 -c "
import json
try:
    with open('./Reports/coverage_report.json', 'r') as f:
        data = json.load(f)
    coverage = data.get('lineCoverage', 0) * 100
    print(f'{coverage:.1f}')
except:
    print('N/A')
" 2>/dev/null || echo "N/A")
fi

# 生成CI友好的测试摘要
echo "📋 生成测试摘要..."

cat > "./Reports/test_summary.txt" << EOF
======================================
       测试执行摘要报告
======================================
执行时间: $(date)
项目名称: $PROJECT_NAME
测试持续时间: ${TEST_DURATION}s
代码覆盖率: ${COVERAGE_PERCENTAGE}%
======================================

测试环境信息:
- Xcode: $XCODE_VERSION
- macOS: $MACOS_VERSION  
- Swift: $SWIFT_VERSION

测试结果文件:
- 详细结果: ./TestResults/CITestResults.xcresult
- 测试报告: ./Reports/test_results.json
- 覆盖率报告: ./Reports/coverage_report.json

$(date): 测试执行完成
======================================
EOF

# 输出最终结果
echo ""
echo "========================================"
echo "            测试完成报告"
echo "========================================"
echo "✅ 总体状态: 通过"
echo "⏱️  执行时间: ${TEST_DURATION}s"
if [ "$COVERAGE_PERCENTAGE" != "N/A" ]; then
    echo "📊 代码覆盖率: ${COVERAGE_PERCENTAGE}%"
fi
echo "📁 报告位置: ./Reports/"
echo "========================================"

# 检查覆盖率阈值 (如果设置了的话)
MIN_COVERAGE_THRESHOLD=${MIN_COVERAGE_THRESHOLD:-70}

if [ "$COVERAGE_PERCENTAGE" != "N/A" ]; then
    COVERAGE_INT=$(echo "$COVERAGE_PERCENTAGE" | cut -d. -f1)
    if [ "$COVERAGE_INT" -lt "$MIN_COVERAGE_THRESHOLD" ]; then
        echo "⚠️  警告: 代码覆盖率 (${COVERAGE_PERCENTAGE}%) 低于阈值 (${MIN_COVERAGE_THRESHOLD}%)"
        # 在CI环境中，可以根据需要决定是否要因此失败
        # exit 1
    else
        echo "✅ 代码覆盖率达标"
    fi
fi

# 生成徽章信息 (用于README等)
if [ "$COVERAGE_PERCENTAGE" != "N/A" ]; then
    echo "coverage-${COVERAGE_PERCENTAGE}%-brightgreen" > "./Reports/coverage_badge.txt"
fi

echo "tests-passing-brightgreen" > "./Reports/test_badge.txt"

echo ""
echo "🎉 CI测试流程完成！"

exit 0
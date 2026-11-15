#!/bin/bash

# 测试套件验证脚本
# 验证测试文件结构和基本配置
# 创建时间: 2025-08-11

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}      测试套件结构验证${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# 检查项目结构
echo -e "${YELLOW}🔍 检查项目结构...${NC}"

PROJECT_ROOT="../"
TEST_DIR="../VoiceTranslationTests"

# 检查主项目文件
echo "检查主项目文件..."
if [ -d "$PROJECT_ROOT/VoiceTranslation.xcodeproj" ]; then
    echo -e "${GREEN}✅ 找到 VoiceTranslation.xcodeproj${NC}"
else
    echo -e "${RED}❌ 未找到项目文件${NC}"
    exit 1
fi

# 检查源码文件
echo "检查源码文件..."
SOURCE_FILES=(
    "VoiceTranslation/ViewModels/MainViewModel.swift"
    "VoiceTranslation/Services/SpeechRecognizer.swift"
    "VoiceTranslation/Services/TranslationService.swift"
    "VoiceTranslation/Services/HistoryManager.swift"
    "VoiceTranslation/Models/TranslationRecord.swift"
    "VoiceTranslation/Models/AppSettings.swift"
    "VoiceTranslation/Utils/ErrorHandler.swift"
)

SOURCE_COUNT=0
for file in "${SOURCE_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        echo -e "${GREEN}✅ $file${NC}"
        ((SOURCE_COUNT++))
    else
        echo -e "${RED}❌ $file${NC}"
    fi
done

echo -e "${BLUE}源码文件检查: $SOURCE_COUNT/${#SOURCE_FILES[@]}${NC}"
echo ""

# 检查测试文件结构
echo -e "${YELLOW}🧪 检查测试文件结构...${NC}"

TEST_FILES=(
    "VoiceTranslationTests.swift"
    "Services/SpeechRecognizerTests.swift"
    "Services/TranslationServiceTests.swift"
    "Services/HistoryManagerTests.swift"
    "ViewModels/MainViewModelTests.swift"
    "Models/ModelTests.swift"
    "Integration/IntegrationTests.swift"
    "Utils/TestUtilities.swift"
)

TEST_COUNT=0
for file in "${TEST_FILES[@]}"; do
    if [ -f "$TEST_DIR/$file" ]; then
        echo -e "${GREEN}✅ $file${NC}"
        ((TEST_COUNT++))
    else
        echo -e "${RED}❌ $file 缺失${NC}"
    fi
done

echo -e "${BLUE}测试文件检查: $TEST_COUNT/${#TEST_FILES[@]}${NC}"
echo ""

# 检查脚本文件
echo -e "${YELLOW}📜 检查脚本文件...${NC}"

SCRIPT_FILES=(
    "scripts/run_tests.sh"
    "scripts/ci_tests.sh"
    "scripts/validate_tests.sh"
)

SCRIPT_COUNT=0
for file in "${SCRIPT_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        if [ -x "$PROJECT_ROOT/$file" ]; then
            echo -e "${GREEN}✅ $file (可执行)${NC}"
        else
            echo -e "${YELLOW}⚠️  $file (不可执行)${NC}"
        fi
        ((SCRIPT_COUNT++))
    else
        echo -e "${RED}❌ $file 缺失${NC}"
    fi
done

echo -e "${BLUE}脚本文件检查: $SCRIPT_COUNT/${#SCRIPT_FILES[@]}${NC}"
echo ""

# 检查测试文件内容
echo -e "${YELLOW}📋 检查测试文件内容...${NC}"

CONTENT_CHECKS=0
TOTAL_CONTENT_CHECKS=0

# 检查主测试文件
if [ -f "$TEST_DIR/VoiceTranslationTests.swift" ]; then
    ((TOTAL_CONTENT_CHECKS++))
    if grep -q "testPerformanceExample" "$TEST_DIR/VoiceTranslationTests.swift" && \
       grep -q "testMemoryLeakage" "$TEST_DIR/VoiceTranslationTests.swift"; then
        echo -e "${GREEN}✅ VoiceTranslationTests.swift 包含性能和内存测试${NC}"
        ((CONTENT_CHECKS++))
    else
        echo -e "${YELLOW}⚠️  VoiceTranslationTests.swift 缺少关键测试方法${NC}"
    fi
fi

# 检查语音识别测试
if [ -f "$TEST_DIR/Services/SpeechRecognizerTests.swift" ]; then
    ((TOTAL_CONTENT_CHECKS++))
    if grep -q "testSpeechRecognizerInitialization" "$TEST_DIR/Services/SpeechRecognizerTests.swift" && \
       grep -q "testRecordingStateManagement" "$TEST_DIR/Services/SpeechRecognizerTests.swift"; then
        echo -e "${GREEN}✅ SpeechRecognizerTests.swift 包含初始化和状态管理测试${NC}"
        ((CONTENT_CHECKS++))
    else
        echo -e "${YELLOW}⚠️  SpeechRecognizerTests.swift 缺少关键测试方法${NC}"
    fi
fi

# 检查翻译服务测试
if [ -f "$TEST_DIR/Services/TranslationServiceTests.swift" ]; then
    ((TOTAL_CONTENT_CHECKS++))
    if grep -q "testTranslationWithoutAPIKey" "$TEST_DIR/Services/TranslationServiceTests.swift" && \
       grep -q "testEnglishToChineseTranslation" "$TEST_DIR/Services/TranslationServiceTests.swift"; then
        echo -e "${GREEN}✅ TranslationServiceTests.swift 包含API和翻译功能测试${NC}"
        ((CONTENT_CHECKS++))
    else
        echo -e "${YELLOW}⚠️  TranslationServiceTests.swift 缺少关键测试方法${NC}"
    fi
fi

# 检查历史管理测试
if [ -f "$TEST_DIR/Services/HistoryManagerTests.swift" ]; then
    ((TOTAL_CONTENT_CHECKS++))
    if grep -q "testSaveTranslationRecord" "$TEST_DIR/Services/HistoryManagerTests.swift" && \
       grep -q "testSearchFiltering" "$TEST_DIR/Services/HistoryManagerTests.swift"; then
        echo -e "${GREEN}✅ HistoryManagerTests.swift 包含保存和搜索测试${NC}"
        ((CONTENT_CHECKS++))
    else
        echo -e "${YELLOW}⚠️  HistoryManagerTests.swift 缺少关键测试方法${NC}"
    fi
fi

echo -e "${BLUE}内容检查: $CONTENT_CHECKS/$TOTAL_CONTENT_CHECKS${NC}"
echo ""

# 检查文档文件
echo -e "${YELLOW}📚 检查文档文件...${NC}"

DOC_FILES=(
    "docs/guides/README_TESTING.md"
)

DOC_COUNT=0
for file in "${DOC_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        echo -e "${GREEN}✅ $file${NC}"
        ((DOC_COUNT++))
    else
        echo -e "${YELLOW}⚠️  $file 缺失${NC}"
    fi
done

echo -e "${BLUE}文档文件检查: $DOC_COUNT/${#DOC_FILES[@]}${NC}"
echo ""

# 计算总体分数
TOTAL_ITEMS=$((${#SOURCE_FILES[@]} + ${#TEST_FILES[@]} + ${#SCRIPT_FILES[@]} + $TOTAL_CONTENT_CHECKS + ${#DOC_FILES[@]}))
PASSED_ITEMS=$(($SOURCE_COUNT + $TEST_COUNT + $SCRIPT_COUNT + $CONTENT_CHECKS + $DOC_COUNT))
SCORE=$(( (PASSED_ITEMS * 100) / TOTAL_ITEMS ))

# 生成最终报告
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}           验证结果摘要${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}总体评分: $SCORE/100${NC}"
echo ""

if [ $SCORE -ge 90 ]; then
    echo -e "${GREEN}🎉 优秀! 测试套件结构完整${NC}"
    STATUS="优秀"
    COLOR=$GREEN
elif [ $SCORE -ge 80 ]; then
    echo -e "${YELLOW}👍 良好! 测试套件基本完整${NC}"
    STATUS="良好"
    COLOR=$YELLOW
elif [ $SCORE -ge 70 ]; then
    echo -e "${YELLOW}⚠️  一般，需要补充一些文件${NC}"
    STATUS="一般"
    COLOR=$YELLOW
else
    echo -e "${RED}❌ 需要改进，缺少重要文件${NC}"
    STATUS="需要改进"
    COLOR=$RED
fi

echo ""
echo "详细统计:"
echo "- 源码文件: $SOURCE_COUNT/${#SOURCE_FILES[@]}"
echo "- 测试文件: $TEST_COUNT/${#TEST_FILES[@]}"
echo "- 脚本文件: $SCRIPT_COUNT/${#SCRIPT_FILES[@]}"
echo "- 内容检查: $CONTENT_CHECKS/$TOTAL_CONTENT_CHECKS"
echo "- 文档文件: $DOC_COUNT/${#DOC_FILES[@]}"

echo ""
echo -e "${BLUE}💡 下一步建议:${NC}"

if [ $SOURCE_COUNT -lt ${#SOURCE_FILES[@]} ]; then
    echo "  - 确保所有源码文件都已正确创建"
fi

if [ $TEST_COUNT -lt ${#TEST_FILES[@]} ]; then
    echo "  - 补充缺失的测试文件"
fi

if [ $SCRIPT_COUNT -lt ${#SCRIPT_FILES[@]} ]; then
    echo "  - 创建缺失的脚本文件并设置执行权限"
fi

if [ $CONTENT_CHECKS -lt $TOTAL_CONTENT_CHECKS ]; then
    echo "  - 确保测试文件包含所有必要的测试方法"
fi

echo "  - 使用 ./run_tests.sh 运行完整测试套件"
echo "  - 查看 docs/guides/README_TESTING.md 了解详细使用说明"

echo ""
echo -e "${COLOR}状态: $STATUS ($SCORE/100)${NC}"
echo -e "${BLUE}===========================================${NC}"

# 设置退出代码
if [ $SCORE -ge 80 ]; then
    exit 0
else
    exit 1
fi
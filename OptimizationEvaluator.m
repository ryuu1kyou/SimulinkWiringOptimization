classdef OptimizationEvaluator < handle
    % OPTIMIZATIONEVALUATOR 最適化結果の評価を行うクラス
    %
    % このクラスは、配線最適化の結果をAI評価とメトリクス計算により
    % 定量的・定性的に評価します。
    
    properties (Access = private)
        config_         % OptimizationConfigオブジェクト
        fileManager_    % FileManagerオブジェクト
        evaluationHistory_ % 評価履歴
    end
    
    methods
        function obj = OptimizationEvaluator(config, fileManager)
            % コンストラクタ
            %
            % 入力:
            %   config - OptimizationConfigオブジェクト
            %   fileManager - FileManagerオブジェクト
            
            if nargin < 1 || ~isa(config, 'OptimizationConfig')
                error('OptimizationEvaluator:InvalidConfig', 'OptimizationConfigオブジェクトが必要です');
            end
            
            if nargin < 2 || ~isa(fileManager, 'FileManager')
                error('OptimizationEvaluator:InvalidFileManager', 'FileManagerオブジェクトが必要です');
            end
            
            obj.config_ = config;
            obj.fileManager_ = fileManager;
            obj.evaluationHistory_ = [];
        end
        
        function result = evaluateWithAI(obj, beforeImagePath, afterImagePath)
            % AI評価を使用して最適化結果を評価
            %
            % 入力:
            %   beforeImagePath - 最適化前の画像パス
            %   afterImagePath - 最適化後の画像パス
            %
            % 出力:
            %   result - 評価結果の構造体
            
            result = struct();
            result.timestamp = now;
            result.beforeImage = beforeImagePath;
            result.afterImage = afterImagePath;
            result.score = -1;
            result.feedback = '';
            result.success = false;
            
            try
                if obj.config_.verbose
                    fprintf('AI評価を実行中...\n');
                end
                
                % Pythonスクリプトの存在確認
                pythonScript = 'evaluate_simulink_image.py';
                if ~exist(pythonScript, 'file')
                    warning('OptimizationEvaluator:ScriptNotFound', ...
                        '評価スクリプトが見つかりません: %s', pythonScript);
                    result.feedback = 'AI評価スクリプトが見つかりません';
                    return;
                end
                
                % 画像ファイルの存在確認
                if ~exist(afterImagePath, 'file')
                    warning('OptimizationEvaluator:ImageNotFound', ...
                        '画像ファイルが見つかりません: %s', afterImagePath);
                    result.feedback = '評価対象の画像ファイルが見つかりません';
                    return;
                end
                
                % Pythonコマンドを構築
                if exist(beforeImagePath, 'file')
                    cmd = sprintf('python "%s" "%s" "%s"', pythonScript, afterImagePath, beforeImagePath);
                else
                    cmd = sprintf('python "%s" "%s"', pythonScript, afterImagePath);
                end
                
                % コマンド実行
                [status, output] = system(cmd);
                
                if status == 0
                    result = obj.parseAIOutput(output, result);
                    result.success = true;
                    
                    if obj.config_.verbose
                        fprintf('AI評価完了 - スコア: %d/100\n', result.score);
                    end
                else
                    result.feedback = sprintf('AI評価の実行に失敗: %s', output);
                    
                    if obj.config_.verbose
                        fprintf('AI評価の実行に失敗\n');
                        fprintf('エラー: %s\n', output);
                    end
                end
                
            catch ME
                result.feedback = sprintf('AI評価中にエラーが発生: %s', ME.message);
                
                if obj.config_.verbose
                    warning('OptimizationEvaluator:AIEvaluationFailed', ...
                        'AI評価中にエラーが発生: %s', ME.message);
                end
            end
            
            % 評価履歴に追加
            obj.evaluationHistory_ = [obj.evaluationHistory_; result];
        end
        
        function result = parseAIOutput(obj, output, result)
            % AI出力を解析
            
            try
                % 出力をログに記録
                result.rawOutput = output;
                
                % スコアを抽出
                scoreMatch = regexp(output, 'SCORE:(\d+)', 'tokens');
                if ~isempty(scoreMatch)
                    result.score = str2double(scoreMatch{1}{1});
                else
                    % 別のパターンでスコアを検索
                    scoreMatch = regexp(output, '(\d+)/100', 'tokens');
                    if ~isempty(scoreMatch)
                        result.score = str2double(scoreMatch{1}{1});
                    else
                        result.score = 50; % デフォルトスコア
                    end
                end
                
                % フィードバックテキストを抽出
                lines = strsplit(output, '\n');
                feedbackLines = {};
                
                for i = 1:length(lines)
                    line = strtrim(lines{i});
                    if ~isempty(line) && ~startsWith(line, 'SCORE:') && ~startsWith(line, 'Final score:')
                        feedbackLines{end+1} = line;
                    end
                end
                
                result.feedback = strjoin(feedbackLines, '\n');
                
            catch ME
                if obj.config_.verbose
                    warning('AI出力の解析に失敗: %s', ME.message);
                end
                result.score = 50;
                result.feedback = 'AI出力の解析に失敗しました';
            end
        end
        
        function metrics = calculateMetrics(obj, systemName)
            % システムのメトリクスを計算
            %
            % 入力:
            %   systemName - システム名
            %
            % 出力:
            %   metrics - メトリクス構造体
            
            metrics = struct();
            metrics.timestamp = now;
            metrics.systemName = systemName;
            
            try
                % 信号線の統計を取得
                lines = find_system(systemName, 'FindAll', 'on', 'Type', 'Line');
                metrics.totalLines = length(lines);
                
                if metrics.totalLines == 0
                    metrics = obj.initializeEmptyMetrics(metrics);
                    return;
                end
                
                % 線の詳細分析
                [straightLineCount, totalSegments, totalLength, complexLines] = ...
                    obj.analyzeLineDetails(lines);
                
                % メトリクスを計算
                metrics.straightLineCount = straightLineCount;
                metrics.totalSegments = totalSegments;
                metrics.totalLength = totalLength;
                metrics.complexLines = complexLines;
                
                % 比率の計算
                if metrics.totalLines > 0
                    metrics.straightLineRatio = straightLineCount / metrics.totalLines * 100;
                    metrics.averageSegmentsPerLine = totalSegments / metrics.totalLines;
                    metrics.averageLineLength = totalLength / metrics.totalLines;
                    metrics.complexLineRatio = complexLines / metrics.totalLines * 100;
                else
                    metrics = obj.initializeEmptyMetrics(metrics);
                end
                
                % ブロック情報
                blocks = find_system(systemName, 'SearchDepth', 1, 'Type', 'Block');
                metrics.blockCount = length(blocks) - 1; % システム自体を除外
                
                % レイアウト密度の計算
                metrics.layoutDensity = obj.calculateLayoutDensity(systemName);
                
                % 品質スコアの計算
                metrics.qualityScore = obj.calculateQualityScore(metrics);
                
            catch ME
                if obj.config_.verbose
                    warning('メトリクス計算に失敗: %s', ME.message);
                end
                metrics = obj.initializeEmptyMetrics(metrics);
            end
        end
        
        function metrics = initializeEmptyMetrics(obj, metrics)
            % 空のメトリクスを初期化
            metrics.totalLines = 0;
            metrics.straightLineCount = 0;
            metrics.totalSegments = 0;
            metrics.totalLength = 0;
            metrics.complexLines = 0;
            metrics.straightLineRatio = 0;
            metrics.averageSegmentsPerLine = 0;
            metrics.averageLineLength = 0;
            metrics.complexLineRatio = 0;
            metrics.blockCount = 0;
            metrics.layoutDensity = 0;
            metrics.qualityScore = 0;
        end
        
        function [straightCount, totalSegments, totalLength, complexCount] = analyzeLineDetails(obj, lines)
            % 線の詳細を分析
            
            straightCount = 0;
            totalSegments = 0;
            totalLength = 0;
            complexCount = 0;
            tolerance = obj.config_.wiringParams.tolerance;
            
            for i = 1:length(lines)
                try
                    points = get_param(lines(i), 'Points');
                    segments = size(points, 1) - 1;
                    totalSegments = totalSegments + segments;
                    
                    % 線長を計算
                    lineLength = 0;
                    for j = 1:segments
                        segmentLength = norm(points(j+1, :) - points(j, :));
                        lineLength = lineLength + segmentLength;
                    end
                    totalLength = totalLength + lineLength;
                    
                    % 直線かどうかチェック
                    if obj.isLineStraight(points, tolerance)
                        straightCount = straightCount + 1;
                    end
                    
                    % 複雑な線かどうかチェック
                    if segments > 3
                        complexCount = complexCount + 1;
                    end
                    
                catch
                    % エラーの場合はスキップ
                end
            end
        end
        
        function straight = isLineStraight(obj, points, tolerance)
            % 線が直線（水平または垂直）かチェック
            
            straight = false;
            
            if size(points, 1) < 2
                return;
            end
            
            % 全セグメントが水平または垂直かチェック
            for i = 1:size(points, 1)-1
                p1 = points(i, :);
                p2 = points(i+1, :);
                
                % 水平または垂直でない場合
                if abs(p1(1) - p2(1)) > tolerance && abs(p1(2) - p2(2)) > tolerance
                    return;
                end
            end
            
            straight = true;
        end
        
        function density = calculateLayoutDensity(obj, systemName)
            % レイアウト密度を計算
            
            density = 0;
            
            try
                blocks = find_system(systemName, 'SearchDepth', 1, 'Type', 'Block');
                blocks = blocks(2:end); % システム自体を除外
                
                if isempty(blocks)
                    return;
                end
                
                % ブロック位置を取得
                positions = [];
                for i = 1:length(blocks)
                    try
                        pos = get_param(blocks{i}, 'Position');
                        positions = [positions; pos];
                    catch
                        % エラーの場合はスキップ
                    end
                end
                
                if ~isempty(positions)
                    % 境界ボックスを計算
                    minX = min(positions(:, 1));
                    minY = min(positions(:, 2));
                    maxX = max(positions(:, 3));
                    maxY = max(positions(:, 4));
                    
                    layoutArea = (maxX - minX) * (maxY - minY);
                    if layoutArea > 0
                        density = length(blocks) / layoutArea * 10000; % 正規化
                    end
                end
                
            catch
                % エラーの場合は0を返す
            end
        end
        
        function score = calculateQualityScore(obj, metrics)
            % 品質スコアを計算（0-100）
            
            % 重み付きスコア計算
            straightLineWeight = 0.4;
            segmentWeight = 0.3;
            complexityWeight = 0.3;
            
            % 直線率スコア（高いほど良い）
            straightScore = min(metrics.straightLineRatio, 100);
            
            % セグメント数スコア（少ないほど良い）
            if metrics.averageSegmentsPerLine > 0
                segmentScore = max(0, 100 - (metrics.averageSegmentsPerLine - 2) * 20);
            else
                segmentScore = 100;
            end
            
            % 複雑さスコア（少ないほど良い）
            complexityScore = max(0, 100 - metrics.complexLineRatio);
            
            % 総合スコア
            score = straightLineWeight * straightScore + ...
                   segmentWeight * segmentScore + ...
                   complexityWeight * complexityScore;
            
            score = max(0, min(100, score));
        end
        
        function report = generateReport(obj, metrics, aiResult)
            % 評価レポートを生成
            %
            % 入力:
            %   metrics - メトリクス構造体
            %   aiResult - AI評価結果（オプション）
            
            report = struct();
            report.timestamp = now;
            report.metrics = metrics;
            
            if nargin > 2 && ~isempty(aiResult)
                report.aiResult = aiResult;
            end
            
            % テキストレポートを生成
            reportText = obj.formatReportText(metrics, aiResult);
            report.text = reportText;
            
            if obj.config_.verbose
                fprintf('\n%s\n', reportText);
            end
        end
        
        function reportText = formatReportText(obj, metrics, aiResult)
            % レポートテキストをフォーマット
            
            reportText = sprintf('=== 配線最適化評価レポート ===\n');
            reportText = [reportText, sprintf('評価日時: %s\n', datestr(metrics.timestamp))];
            reportText = [reportText, sprintf('対象システム: %s\n\n', metrics.systemName)];
            
            % メトリクス情報
            reportText = [reportText, sprintf('--- メトリクス ---\n')];
            reportText = [reportText, sprintf('総信号線数: %d\n', metrics.totalLines)];
            reportText = [reportText, sprintf('直線数: %d\n', metrics.straightLineCount)];
            reportText = [reportText, sprintf('直線率: %.1f%%\n', metrics.straightLineRatio)];
            reportText = [reportText, sprintf('平均セグメント数: %.1f\n', metrics.averageSegmentsPerLine)];
            reportText = [reportText, sprintf('平均線長: %.1f\n', metrics.averageLineLength)];
            reportText = [reportText, sprintf('複雑線率: %.1f%%\n', metrics.complexLineRatio)];
            reportText = [reportText, sprintf('品質スコア: %.1f/100\n\n', metrics.qualityScore)];
            
            % AI評価結果
            if nargin > 2 && ~isempty(aiResult) && aiResult.success
                reportText = [reportText, sprintf('--- AI評価 ---\n')];
                reportText = [reportText, sprintf('AIスコア: %d/100\n', aiResult.score)];
                if ~isempty(aiResult.feedback)
                    reportText = [reportText, sprintf('フィードバック:\n%s\n\n', aiResult.feedback)];
                end
            end
            
            reportText = [reportText, sprintf('========================\n')];
        end
        
        function saveComparisonImages(obj, systemName, suffix)
            % 比較用画像を保存
            %
            % 入力:
            %   systemName - システム名
            %   suffix - ファイル名サフィックス（オプション）
            
            if nargin < 3
                suffix = datestr(now, 'yyyymmdd_HHMMSS');
            end
            
            try
                % 最適化後の画像を保存
                afterImagePath = obj.fileManager_.generateImagePath(systemName, ['after_', suffix]);
                obj.fileManager_.saveModelImage(systemName, afterImagePath);
                
                if obj.config_.verbose
                    fprintf('比較画像を保存: %s\n', afterImagePath);
                end
                
            catch ME
                if obj.config_.verbose
                    warning('比較画像の保存に失敗: %s', ME.message);
                end
            end
        end
        
        function history = getEvaluationHistory(obj)
            % 評価履歴を取得
            history = obj.evaluationHistory_;
        end
        
        function clearHistory(obj)
            % 評価履歴をクリア
            obj.evaluationHistory_ = [];
        end
    end
end

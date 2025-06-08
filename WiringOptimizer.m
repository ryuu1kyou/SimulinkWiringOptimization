classdef WiringOptimizer < handle
    % WIRINGOPTIMIZER 配線最適化を行うクラス
    %
    % このクラスは、Simulinkモデルの配線を人間の最適化プロセスに基づいて
    % 自動的に改善します。
    
    properties (Access = private)
        config_             % OptimizationConfigオブジェクト
        optimizationStats_  % 最適化統計情報
    end
    
    methods
        function obj = WiringOptimizer(config)
            % コンストラクタ
            %
            % 入力:
            %   config - OptimizationConfigオブジェクト
            
            if nargin < 1 || ~isa(config, 'OptimizationConfig')
                error('WiringOptimizer:InvalidConfig', 'OptimizationConfigオブジェクトが必要です');
            end
            
            obj.config_ = config;
            obj.resetStats();
        end
        
        function resetStats(obj)
            % 統計情報をリセット
            obj.optimizationStats_ = struct();
            obj.optimizationStats_.totalLinesProcessed = 0;
            obj.optimizationStats_.linesOptimized = 0;
            obj.optimizationStats_.subsystemsProcessed = 0;
            obj.optimizationStats_.startTime = now;
            obj.optimizationStats_.errors = {};
        end
        
        function optimizeAllSubsystems(obj, modelName)
            % モデル内の全サブシステムを最適化
            %
            % 入力:
            %   modelName - モデル名
            
            if obj.config_.verbose
                fprintf('全サブシステムの最適化を開始: %s\n', modelName);
            end
            
            try
                % サブシステムの検索
                subsystems = find_system(modelName, 'BlockType', 'SubSystem');
                
                % リンクライブラリの除外
                validSubsystems = obj.filterValidSubsystems(subsystems);
                
                % トップレベルの最適化
                if obj.config_.verbose
                    fprintf('  トップレベルを最適化: %s\n', modelName);
                end
                obj.optimizeSubsystemWiring(modelName);
                
                % 各サブシステムの最適化
                for i = 1:length(validSubsystems)
                    if obj.config_.verbose
                        fprintf('  サブシステムを最適化 (%d/%d): %s\n', ...
                            i, length(validSubsystems), validSubsystems{i});
                    end
                    obj.optimizeSubsystemWiring(validSubsystems{i});
                end
                
                if obj.config_.verbose
                    fprintf('全サブシステムの最適化完了\n');
                    obj.displayOptimizationStats();
                end
                
            catch ME
                obj.optimizationStats_.errors{end+1} = ME.message;
                error('WiringOptimizer:OptimizationFailed', ...
                    '最適化に失敗: %s', ME.message);
            end
        end
        
        function validSubsystems = filterValidSubsystems(obj, subsystems)
            % 有効なサブシステムをフィルタリング
            
            validSubsystems = {};
            
            for i = 1:length(subsystems)
                try
                    linkStatus = get_param(subsystems{i}, 'LinkStatus');
                    if strcmp(linkStatus, 'none')
                        validSubsystems{end+1} = subsystems{i};
                    else
                        if obj.config_.verbose
                            fprintf('  リンクライブラリをスキップ: %s\n', subsystems{i});
                        end
                    end
                catch
                    % LinkStatusが取得できない場合は有効とみなす
                    validSubsystems{end+1} = subsystems{i};
                end
            end
        end
        
        function optimizeSubsystemWiring(obj, subsystemName)
            % 指定されたサブシステムの配線最適化
            %
            % 入力:
            %   subsystemName - サブシステム名
            
            if obj.config_.verbose
                fprintf('    配線最適化中: %s\n', subsystemName);
            end
            
            obj.optimizationStats_.subsystemsProcessed = ...
                obj.optimizationStats_.subsystemsProcessed + 1;
            
            try
                % サブシステム内の信号線を取得
                lines = obj.getSystemLines(subsystemName);
                
                if isempty(lines)
                    if obj.config_.verbose
                        fprintf('      信号線が見つかりません\n');
                    end
                    return;
                end
                
                if obj.config_.verbose
                    fprintf('      信号線数: %d\n', length(lines));
                end
                
                % 各信号線の最適化
                optimizedCount = 0;
                for i = 1:length(lines)
                    if obj.optimizeSingleLine(lines(i))
                        optimizedCount = optimizedCount + 1;
                    end
                    obj.optimizationStats_.totalLinesProcessed = ...
                        obj.optimizationStats_.totalLinesProcessed + 1;
                end
                
                obj.optimizationStats_.linesOptimized = ...
                    obj.optimizationStats_.linesOptimized + optimizedCount;
                
                if obj.config_.verbose
                    fprintf('      最適化された信号線: %d/%d\n', optimizedCount, length(lines));
                end
                
                % 交差の最適化
                if optimizedCount > 0
                    obj.optimizeCrossings(subsystemName, lines);
                end
                
            catch ME
                errorMsg = sprintf('配線最適化中にエラー: %s (%s)', subsystemName, ME.message);
                obj.optimizationStats_.errors{end+1} = errorMsg;
                
                if obj.config_.verbose
                    warning('WiringOptimizer:SubsystemOptimizationFailed', errorMsg);
                end
            end
        end
        
        function lines = getSystemLines(obj, systemName)
            % システム内の信号線を取得
            
            try
                lineHandles = find_system(systemName, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'Line');
                lines = [];
                
                for i = 1:length(lineHandles)
                    try
                        line = SimulinkLine(lineHandles(i));
                        lines = [lines; line];
                    catch
                        % 無効な線はスキップ
                    end
                end
                
            catch ME
                warning('WiringOptimizer:GetLinesFailed', ...
                    '信号線の取得に失敗: %s', ME.message);
                lines = [];
            end
        end
        
        function success = optimizeSingleLine(obj, line)
            % 単一の信号線を最適化
            %
            % 入力:
            %   line - SimulinkLineオブジェクト
            %
            % 出力:
            %   success - 最適化の成功/失敗
            
            success = false;
            
            try
                if ~isa(line, 'SimulinkLine')
                    return;
                end
                
                originalPoints = line.getPoints();
                
                if size(originalPoints, 1) < 2
                    return; % 点が不十分
                end
                
                optimized = false;
                
                if obj.config_.preserveLines
                    % 既存線を保持しながら最適化
                    if line.straighten('auto')
                        optimized = true;
                    end
                    
                    if line.removeRedundantPoints()
                        optimized = true;
                    end
                else
                    % より積極的な最適化
                    newPoints = obj.createOptimalPath(originalPoints(1,:), originalPoints(end,:));
                    
                    if ~isequal(originalPoints, newPoints)
                        line.setPoints(newPoints);
                        optimized = true;
                    end
                end
                
                success = optimized;
                
            catch ME
                if obj.config_.verbose
                    warning('単一線の最適化に失敗: %s', ME.message);
                end
            end
        end
        
        function optimalPoints = createOptimalPath(obj, startPoint, endPoint)
            % 開始点と終了点間の最適パスを作成
            %
            % 入力:
            %   startPoint - 開始点 [x, y]
            %   endPoint - 終了点 [x, y]
            %
            % 出力:
            %   optimalPoints - 最適化された点の配列
            
            params = obj.config_.wiringParams;
            
            % 単純な直角パスを作成
            deltaX = abs(startPoint(1) - endPoint(1));
            deltaY = abs(startPoint(2) - endPoint(2));
            
            if deltaX > deltaY
                % 水平方向が主
                midY = startPoint(2);
                optimalPoints = [startPoint; endPoint(1), midY; endPoint];
            else
                % 垂直方向が主
                midX = startPoint(1);
                optimalPoints = [startPoint; midX, endPoint(2); endPoint];
            end
            
            % 同じ点を除去
            optimalPoints = obj.removeDuplicatePoints(optimalPoints);
            
            % 最小間隔の適用
            optimalPoints = obj.applyMinimumSpacing(optimalPoints, params.minSpacing);
        end
        
        function cleanedPoints = removeDuplicatePoints(obj, points)
            % 重複する点を除去
            
            if size(points, 1) <= 1
                cleanedPoints = points;
                return;
            end
            
            tolerance = obj.config_.wiringParams.tolerance;
            cleanedPoints = points(1, :);
            
            for i = 2:size(points, 1)
                currentPoint = points(i, :);
                lastPoint = cleanedPoints(end, :);
                
                % 距離が許容値より大きい場合のみ追加
                distance = norm(currentPoint - lastPoint);
                if distance > tolerance
                    cleanedPoints = [cleanedPoints; currentPoint];
                end
            end
        end
        
        function spacedPoints = applyMinimumSpacing(obj, points, minSpacing)
            % 最小間隔を適用
            
            if size(points, 1) <= 2 || minSpacing <= 0
                spacedPoints = points;
                return;
            end
            
            spacedPoints = points(1, :); % 開始点
            
            for i = 2:size(points, 1)-1
                currentPoint = points(i, :);
                lastPoint = spacedPoints(end, :);
                
                % 間隔をチェック
                distance = norm(currentPoint - lastPoint);
                if distance >= minSpacing
                    spacedPoints = [spacedPoints; currentPoint];
                else
                    % 最小間隔を満たすように調整
                    direction = (currentPoint - lastPoint) / distance;
                    adjustedPoint = lastPoint + direction * minSpacing;
                    spacedPoints = [spacedPoints; adjustedPoint];
                end
            end
            
            spacedPoints = [spacedPoints; points(end, :)]; % 終了点
        end
        
        function optimizeCrossings(obj, systemName, lines)
            % 線の交差を最適化
            %
            % 入力:
            %   systemName - システム名
            %   lines - 信号線の配列
            
            if length(lines) < 2
                return;
            end
            
            try
                crossingCount = 0;
                adjustmentCount = 0;
                
                % 全ての線のペアをチェック
                for i = 1:length(lines)-1
                    for j = i+1:length(lines)
                        if obj.linesIntersect(lines(i), lines(j))
                            crossingCount = crossingCount + 1;
                            
                            % 交差を解決
                            if obj.resolveCrossing(lines(i), lines(j))
                                adjustmentCount = adjustmentCount + 1;
                            end
                        end
                    end
                end
                
                if obj.config_.verbose && crossingCount > 0
                    fprintf('      交差検出: %d, 調整: %d\n', crossingCount, adjustmentCount);
                end
                
            catch ME
                if obj.config_.verbose
                    warning('交差最適化に失敗: %s', ME.message);
                end
            end
        end
        
        function intersect = linesIntersect(obj, line1, line2)
            % 2つの線が交差するかチェック
            
            intersect = false;
            
            try
                points1 = line1.getPoints();
                points2 = line2.getPoints();
                
                % 簡単な境界ボックスチェック
                bbox1 = [min(points1(:,1)), min(points1(:,2)), max(points1(:,1)), max(points1(:,2))];
                bbox2 = [min(points2(:,1)), min(points2(:,2)), max(points2(:,1)), max(points2(:,2))];
                
                % 境界ボックスが重なっていない場合は交差しない
                if bbox1(3) < bbox2(1) || bbox2(3) < bbox1(1) || ...
                   bbox1(4) < bbox2(2) || bbox2(4) < bbox1(2)
                    return;
                end
                
                % より詳細な交差チェック（簡略版）
                % 実際の実装では、線分の交差判定アルゴリズムを使用
                intersect = true; % 簡略化
                
            catch
                % エラーの場合は交差しないとみなす
            end
        end
        
        function success = resolveCrossing(obj, line1, line2)
            % 線の交差を解決
            
            success = false;
            
            try
                % 簡単な解決策：一方の線を少しオフセット
                params = obj.config_.wiringParams;
                offset = params.baseOffset;
                
                % line1をオフセット
                points1 = line1.getPoints();
                if size(points1, 1) >= 2
                    % Y方向にオフセット
                    offsetPoints = points1;
                    offsetPoints(:, 2) = offsetPoints(:, 2) + offset;
                    
                    line1.setPoints(offsetPoints);
                    success = true;
                end
                
            catch
                % エラーの場合は何もしない
            end
        end
        
        function displayOptimizationStats(obj)
            % 最適化統計を表示
            
            stats = obj.optimizationStats_;
            elapsedTime = (now - stats.startTime) * 24 * 3600; % 秒
            
            fprintf('\n--- 最適化統計 ---\n');
            fprintf('処理時間: %.2f秒\n', elapsedTime);
            fprintf('処理サブシステム数: %d\n', stats.subsystemsProcessed);
            fprintf('処理信号線数: %d\n', stats.totalLinesProcessed);
            fprintf('最適化信号線数: %d\n', stats.linesOptimized);
            
            if stats.totalLinesProcessed > 0
                optimizationRate = stats.linesOptimized / stats.totalLinesProcessed * 100;
                fprintf('最適化率: %.1f%%\n', optimizationRate);
            end
            
            if ~isempty(stats.errors)
                fprintf('エラー数: %d\n', length(stats.errors));
                for i = 1:min(3, length(stats.errors)) % 最初の3つのエラーを表示
                    fprintf('  %s\n', stats.errors{i});
                end
            end
            
            fprintf('------------------\n');
        end
        
        function stats = getOptimizationStats(obj)
            % 最適化統計を取得
            stats = obj.optimizationStats_;
        end
    end
end

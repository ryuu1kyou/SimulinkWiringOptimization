classdef LayoutAnalyzer < handle
    % LAYOUTANALYZER レイアウト分析を行うクラス
    %
    % このクラスは、Simulinkモデルのブロック配置と信号フローを分析し、
    % 配線最適化に必要な情報を提供します。
    
    properties (Access = private)
        config_         % OptimizationConfigオブジェクト
        analysisCache_  % 分析結果のキャッシュ
    end
    
    methods
        function obj = LayoutAnalyzer(config)
            % コンストラクタ
            %
            % 入力:
            %   config - OptimizationConfigオブジェクト
            
            if nargin < 1 || ~isa(config, 'OptimizationConfig')
                error('LayoutAnalyzer:InvalidConfig', 'OptimizationConfigオブジェクトが必要です');
            end
            
            obj.config_ = config;
            obj.analysisCache_ = containers.Map();
        end
        
        function layoutInfo = analyzeLayout(obj, systemName)
            % システムのレイアウトを分析
            %
            % 入力:
            %   systemName - 分析対象のシステム名
            %
            % 出力:
            %   layoutInfo - レイアウト情報の構造体
            
            % キャッシュをチェック
            if obj.analysisCache_.isKey(systemName)
                layoutInfo = obj.analysisCache_(systemName);
                if obj.config_.verbose
                    fprintf('キャッシュからレイアウト情報を取得: %s\n', systemName);
                end
                return;
            end
            
            if obj.config_.verbose
                fprintf('レイアウト分析中: %s\n', systemName);
            end
            
            % 基本情報の取得
            layoutInfo = struct();
            layoutInfo.systemName = systemName;
            layoutInfo.timestamp = now;
            
            % ブロック情報の分析
            layoutInfo.blocks = obj.analyzeBlocks(systemName);
            layoutInfo.blockCount = length(layoutInfo.blocks);
            
            % 信号線情報の分析
            layoutInfo.lines = obj.analyzeLines(systemName);
            layoutInfo.lineCount = length(layoutInfo.lines);
            
            % 境界ボックスの計算
            layoutInfo.boundingBox = obj.calculateBoundingBox(layoutInfo.blocks);
            
            % 信号フローの分析
            layoutInfo.signalFlow = obj.analyzeSignalFlow(layoutInfo.blocks, layoutInfo.lines);
            
            % レイアウト品質メトリクスの計算
            layoutInfo.metrics = obj.calculateLayoutMetrics(layoutInfo);
            
            % キャッシュに保存
            obj.analysisCache_(systemName) = layoutInfo;
            
            if obj.config_.verbose
                obj.displayLayoutSummary(layoutInfo);
            end
        end
        
        function blocks = analyzeBlocks(obj, systemName)
            % ブロック情報を分析
            
            blocks = [];
            
            try
                % ブロックパスを取得
                blockPaths = find_system(systemName, 'SearchDepth', 1, 'Type', 'Block');
                blockPaths = blockPaths(2:end); % システム自体を除外
                
                % 各ブロックの情報を取得
                for i = 1:length(blockPaths)
                    try
                        block = SimulinkBlock(blockPaths{i});
                        blockInfo = block.getBlockInfo();
                        blocks = [blocks; blockInfo];
                    catch ME
                        if obj.config_.verbose
                            warning('ブロック情報の取得に失敗: %s (%s)', blockPaths{i}, ME.message);
                        end
                    end
                end
                
            catch ME
                warning('LayoutAnalyzer:BlockAnalysisFailed', ...
                    'ブロック分析に失敗: %s', ME.message);
            end
        end
        
        function lines = analyzeLines(obj, systemName)
            % 信号線情報を分析
            
            lines = [];
            
            try
                % 信号線ハンドルを取得
                lineHandles = find_system(systemName, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'Line');
                
                % 各信号線の情報を取得
                for i = 1:length(lineHandles)
                    try
                        line = SimulinkLine(lineHandles(i));
                        lineInfo = struct();
                        lineInfo.handle = line.handle;
                        lineInfo.points = line.points;
                        lineInfo.sourceBlock = line.sourceBlock;
                        lineInfo.destinationBlock = line.destinationBlock;
                        lineInfo.lineType = line.lineType;
                        lineInfo.length = line.getLength();
                        lineInfo.segmentCount = line.getSegmentCount();
                        lineInfo.isHorizontal = line.isHorizontal();
                        lineInfo.isVertical = line.isVertical();
                        
                        lines = [lines; lineInfo];
                    catch ME
                        if obj.config_.verbose
                            warning('信号線情報の取得に失敗: ハンドル %d (%s)', lineHandles(i), ME.message);
                        end
                    end
                end
                
            catch ME
                warning('LayoutAnalyzer:LineAnalysisFailed', ...
                    '信号線分析に失敗: %s', ME.message);
            end
        end
        
        function boundingBox = calculateBoundingBox(obj, blocks)
            % ブロック群の境界ボックスを計算
            
            if isempty(blocks)
                boundingBox = [0, 0, 100, 100];
                return;
            end
            
            % 全ブロックの位置を取得
            positions = vertcat(blocks.position);
            
            if isempty(positions)
                boundingBox = [0, 0, 100, 100];
                return;
            end
            
            % 境界ボックスを計算
            minX = min(positions(:, 1));
            minY = min(positions(:, 2));
            maxX = max(positions(:, 3));
            maxY = max(positions(:, 4));
            
            boundingBox = [minX, minY, maxX, maxY];
        end
        
        function signalFlow = analyzeSignalFlow(obj, blocks, lines)
            % 信号フローを分析
            
            signalFlow = struct();
            signalFlow.direction = 'left_to_right'; % デフォルト
            signalFlow.layers = [];
            signalFlow.connections = [];
            
            if isempty(blocks) || isempty(lines)
                return;
            end
            
            try
                % ブロック間の接続関係を分析
                connections = obj.buildConnectionGraph(blocks, lines);
                signalFlow.connections = connections;
                
                % 主要な信号フロー方向を推定
                signalFlow.direction = obj.estimateFlowDirection(blocks, connections);
                
                % レイヤー構造を分析
                signalFlow.layers = obj.identifyLayers(blocks, connections, signalFlow.direction);
                
            catch ME
                warning('LayoutAnalyzer:SignalFlowAnalysisFailed', ...
                    '信号フロー分析に失敗: %s', ME.message);
            end
        end
        
        function connections = buildConnectionGraph(obj, blocks, lines)
            % ブロック間の接続グラフを構築
            
            connections = [];
            
            for i = 1:length(lines)
                line = lines(i);
                
                % 送信元と送信先ブロックを特定
                srcIdx = obj.findBlockIndex(blocks, line.sourceBlock);
                dstIdx = obj.findBlockIndex(blocks, line.destinationBlock);
                
                if srcIdx > 0 && dstIdx > 0
                    connection = struct();
                    connection.source = srcIdx;
                    connection.destination = dstIdx;
                    connection.lineHandle = line.handle;
                    connection.length = line.length;
                    
                    connections = [connections; connection];
                end
            end
        end
        
        function idx = findBlockIndex(obj, blocks, blockName)
            % ブロック名からインデックスを検索
            
            idx = 0;
            
            for i = 1:length(blocks)
                if strcmp(blocks(i).name, blockName)
                    idx = i;
                    return;
                end
            end
        end
        
        function direction = estimateFlowDirection(obj, blocks, connections)
            % 主要な信号フロー方向を推定
            
            direction = 'left_to_right'; % デフォルト
            
            if isempty(connections)
                return;
            end
            
            try
                % 接続の方向ベクトルを計算
                directionVectors = [];
                
                for i = 1:length(connections)
                    conn = connections(i);
                    srcBlock = blocks(conn.source);
                    dstBlock = blocks(conn.destination);
                    
                    srcCenter = srcBlock.center;
                    dstCenter = dstBlock.center;
                    
                    vector = dstCenter - srcCenter;
                    directionVectors = [directionVectors; vector];
                end
                
                % 平均方向ベクトルを計算
                avgVector = mean(directionVectors, 1);
                
                % 主要方向を判定
                if abs(avgVector(1)) > abs(avgVector(2))
                    if avgVector(1) > 0
                        direction = 'left_to_right';
                    else
                        direction = 'right_to_left';
                    end
                else
                    if avgVector(2) > 0
                        direction = 'top_to_bottom';
                    else
                        direction = 'bottom_to_top';
                    end
                end
                
            catch ME
                warning('LayoutAnalyzer:DirectionEstimationFailed', ...
                    '方向推定に失敗: %s', ME.message);
            end
        end
        
        function layers = identifyLayers(obj, blocks, connections, direction)
            % レイヤー構造を特定
            
            layers = [];
            
            if isempty(blocks)
                return;
            end
            
            try
                % 方向に基づいて座標を選択
                switch direction
                    case {'left_to_right', 'right_to_left'}
                        coordinates = vertcat(blocks.center);
                        coordinates = coordinates(:, 1); % X座標
                    case {'top_to_bottom', 'bottom_to_top'}
                        coordinates = vertcat(blocks.center);
                        coordinates = coordinates(:, 2); % Y座標
                    otherwise
                        coordinates = vertcat(blocks.center);
                        coordinates = coordinates(:, 1); % デフォルトはX座標
                end
                
                % クラスタリングによるレイヤー分割
                layers = obj.clusterBlocks(coordinates, blocks);
                
            catch ME
                warning('LayoutAnalyzer:LayerIdentificationFailed', ...
                    'レイヤー特定に失敗: %s', ME.message);
            end
        end
        
        function layers = clusterBlocks(obj, coordinates, blocks)
            % ブロックをクラスタリング
            
            % 簡単なクラスタリング（座標の近さに基づく）
            tolerance = 50; % ピクセル単位
            
            sortedCoords = sort(coordinates);
            layers = {};
            currentLayer = [];
            lastCoord = -inf;
            
            for i = 1:length(sortedCoords)
                coord = sortedCoords(i);
                
                if coord - lastCoord > tolerance
                    % 新しいレイヤーを開始
                    if ~isempty(currentLayer)
                        layers{end+1} = currentLayer;
                    end
                    currentLayer = [];
                end
                
                % 現在のレイヤーにブロックを追加
                blockIdx = find(coordinates == coord, 1);
                currentLayer = [currentLayer; blockIdx];
                lastCoord = coord;
            end
            
            % 最後のレイヤーを追加
            if ~isempty(currentLayer)
                layers{end+1} = currentLayer;
            end
        end
        
        function metrics = calculateLayoutMetrics(obj, layoutInfo)
            % レイアウト品質メトリクスを計算
            
            metrics = struct();
            
            % 基本メトリクス
            metrics.blockCount = layoutInfo.blockCount;
            metrics.lineCount = layoutInfo.lineCount;
            
            if layoutInfo.lineCount > 0
                % 直線率の計算
                straightLines = 0;
                totalSegments = 0;
                
                for i = 1:length(layoutInfo.lines)
                    line = layoutInfo.lines(i);
                    totalSegments = totalSegments + line.segmentCount;
                    
                    if line.isHorizontal || line.isVertical
                        straightLines = straightLines + 1;
                    end
                end
                
                metrics.straightLineRatio = straightLines / layoutInfo.lineCount * 100;
                metrics.averageSegmentsPerLine = totalSegments / layoutInfo.lineCount;
                
                % 平均線長
                totalLength = sum([layoutInfo.lines.length]);
                metrics.averageLineLength = totalLength / layoutInfo.lineCount;
            else
                metrics.straightLineRatio = 0;
                metrics.averageSegmentsPerLine = 0;
                metrics.averageLineLength = 0;
            end
            
            % レイアウト密度
            boundingBox = layoutInfo.boundingBox;
            layoutArea = (boundingBox(3) - boundingBox(1)) * (boundingBox(4) - boundingBox(2));
            metrics.layoutDensity = layoutInfo.blockCount / max(layoutArea, 1);
        end
        
        function displayLayoutSummary(obj, layoutInfo)
            % レイアウト分析結果のサマリーを表示
            
            fprintf('  ブロック数: %d\n', layoutInfo.blockCount);
            fprintf('  信号線数: %d\n', layoutInfo.lineCount);
            fprintf('  境界ボックス: [%.0f, %.0f, %.0f, %.0f]\n', layoutInfo.boundingBox);
            fprintf('  信号フロー方向: %s\n', layoutInfo.signalFlow.direction);
            fprintf('  直線率: %.1f%%\n', layoutInfo.metrics.straightLineRatio);
            fprintf('  平均線長: %.1f\n', layoutInfo.metrics.averageLineLength);
        end
        
        function clearCache(obj)
            % 分析キャッシュをクリア
            obj.analysisCache_ = containers.Map();
        end
        
        function cacheInfo = getCacheInfo(obj)
            % キャッシュ情報を取得
            cacheInfo = struct();
            cacheInfo.entryCount = obj.analysisCache_.Count;
            cacheInfo.keys = keys(obj.analysisCache_);
        end
    end
end

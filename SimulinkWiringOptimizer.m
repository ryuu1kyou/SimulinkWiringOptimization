classdef SimulinkWiringOptimizer < handle
    % SIMULINKWIRINGOPTIMIZER メインの配線最適化オーケストレータークラス
    %
    % このクラスは、Simulink配線最適化プロセス全体を統括し、
    % 各コンポーネントクラスを協調させて最適化を実行します。
    
    properties (Access = private)
        config_         % OptimizationConfigオブジェクト
        fileManager_    % FileManagerオブジェクト
        layoutAnalyzer_ % LayoutAnalyzerオブジェクト
        wiringOptimizer_ % WiringOptimizerオブジェクト
        evaluator_      % OptimizationEvaluatorオブジェクト

        currentModel_   % 現在処理中のモデル名
        optimizationResults_ % 最適化結果
        autoExecute_    % 自動実行フラグ
        modelName_      % 指定されたモデル名
    end
    
    methods
        function obj = SimulinkWiringOptimizer(varargin)
            % コンストラクタ - 配線整理システムを作成
            %
            % 使用法:
            %   optimizer = SimulinkWiringOptimizer()
            %   optimizer = SimulinkWiringOptimizer('fullCarModel.slx')  % 直接実行
            %   optimizer = SimulinkWiringOptimizer('preserveLines', true, 'enableAIEvaluation', false)
            %
            % モデル名を指定した場合は自動的に実行されます

            % 最初の引数がモデル名かどうかチェック
            if nargin > 0 && ischar(varargin{1}) && ~any(strcmp(varargin{1}, ...
                {'preserveLines', 'enableAIEvaluation', 'targetSubsystem', 'verbose', 'outputDirectory', 'wiringParams'}))
                % 最初の引数がモデル名の場合
                modelName = varargin{1};
                configArgs = varargin(2:end);
                obj.autoExecute_ = true;
                obj.modelName_ = modelName;
            else
                % 設定パラメータのみの場合
                configArgs = varargin;
                obj.autoExecute_ = false;
                obj.modelName_ = '';
            end

            % 設定オブジェクトを作成
            obj.config_ = OptimizationConfig(configArgs{:});
            
            % 各コンポーネントを初期化
            obj.fileManager_ = FileManager(obj.config_);
            obj.layoutAnalyzer_ = LayoutAnalyzer(obj.config_);
            obj.wiringOptimizer_ = WiringOptimizer(obj.config_);
            obj.evaluator_ = OptimizationEvaluator(obj.config_, obj.fileManager_);
            
            % 初期化
            obj.currentModel_ = '';
            obj.optimizationResults_ = [];

            if obj.config_.verbose
                fprintf('Simulink配線最適化システムを初期化しました\n');
                obj.config_.displayConfiguration();
            end

            % 自動実行の処理
            if obj.autoExecute_
                if obj.config_.verbose
                    fprintf('モデル "%s" の配線整理を自動実行します...\n', obj.modelName_);
                end
                try
                    result = obj.optimize(obj.modelName_);
                    if result.success
                        fprintf('配線整理が完了しました。\n');
                        obj.displayResults();
                    else
                        fprintf('配線整理に失敗しました: %s\n', result.error);
                    end
                catch ME
                    fprintf('エラーが発生しました: %s\n', ME.message);
                end
            end
        end
        
        function result = optimize(obj, modelName, varargin)
            % メイン最適化関数
            %
            % 入力:
            %   modelName - Simulinkモデルファイルのパス
            %   varargin - 追加のオプション引数
            %
            % 出力:
            %   result - 最適化結果の構造体
            
            % 追加オプションがある場合は設定を更新
            if ~isempty(varargin)
                obj.config_.parseInputArguments(varargin{:});
            end
            
            % 結果構造体を初期化
            result = obj.initializeResult(modelName);
            
            try
                % Phase 1: 前処理
                result = obj.preprocessModel(modelName, result);

                % Phase 2: レイアウト分析
                result = obj.analyzeLayout(result);

                % Phase 3: 配線最適化
                result = obj.performOptimization(result);

                % Phase 4: 評価
                result = obj.evaluateResults(result);

                % Phase 5: 後処理
                result = obj.postprocessResults(result);
                
                result.success = true;
                result.endTime = datetime('now');
                result.elapsedTime = seconds(result.endTime - result.startTime);
                
                if obj.config_.verbose
                    fprintf('\n=== 配線最適化完了 ===\n');
                    fprintf('処理時間: %.2f秒\n', result.elapsedTime);
                    fprintf('成功: %s\n', mat2str(result.success));
                end
                
            catch ME
                result.success = false;
                result.error = ME.message;
                result.endTime = datetime('now');

                if obj.config_.verbose
                    fprintf('\n=== 配線最適化失敗 ===\n');
                    fprintf('エラー: %s\n', ME.message);
                    fprintf('スタックトレース:\n');
                    for i = 1:length(ME.stack)
                        fprintf('  %s (行 %d)\n', ME.stack(i).name, ME.stack(i).line);
                    end
                end

                rethrow(ME);
            end
            
            % 結果を保存
            obj.optimizationResults_ = [obj.optimizationResults_; result];
        end
        
        function result = optimizeSubsystem(obj, modelName, subsystemName, varargin)
            % 特定のサブシステムのみを最適化
            %
            % 入力:
            %   modelName - Simulinkモデルファイルのパス
            %   subsystemName - 対象サブシステム名
            %   varargin - 追加のオプション引数
            
            % サブシステムを設定に追加
            allArgs = [varargin, {'targetSubsystem', subsystemName}];
            result = obj.optimize(modelName, allArgs{:});
        end
        
        function result = initializeResult(obj, modelName)
            % 結果構造体を初期化
            
            result = struct();
            result.modelName = modelName;
            result.targetSubsystem = obj.config_.targetSubsystem;
            result.startTime = datetime('now');
            result.endTime = [];
            result.elapsedTime = 0;
            result.success = false;
            result.error = '';
            
            % 各フェーズの結果
            result.preprocessing = struct();
            result.layoutAnalysis = struct();
            result.optimization = struct();
            result.evaluation = struct();
            result.postprocessing = struct();
        end
        
        function result = preprocessModel(obj, modelName, result)
            % モデルの前処理

            if obj.config_.verbose
                fprintf('\n--- Phase 1: 前処理 ---\n');
            end

            try
                % モデルファイルの存在確認
                if obj.config_.verbose
                    fprintf('モデルファイル存在確認: %s\n', modelName);
                end

                if ~obj.fileManager_.modelExists(modelName)
                    error('SimulinkWiringOptimizer:ModelNotFound', ...
                        'モデルファイルが見つかりません: %s', modelName);
                end

                % バックアップの作成
                if obj.config_.verbose
                    fprintf('バックアップ作成中...\n');
                end
                backupSuccess = obj.fileManager_.createBackup(modelName);
                result.preprocessing.backupCreated = backupSuccess;

                % モデルの読み込み
                if obj.config_.verbose
                    fprintf('モデル読み込み中...\n');
                end
                [loadSuccess, modelBaseName] = obj.fileManager_.loadModel(modelName);
                result.preprocessing.modelLoaded = loadSuccess;
                result.preprocessing.modelBaseName = modelBaseName;

                if obj.config_.verbose
                    fprintf('モデルベース名を設定: %s\n', modelBaseName);
                    fprintf('デバッグ: result.preprocessing.modelBaseName = "%s"\n', result.preprocessing.modelBaseName);
                    fprintf('デバッグ: loadSuccess = %s\n', mat2str(loadSuccess));
                end

                % 読み込みが失敗した場合のチェック
                if ~loadSuccess || isempty(modelBaseName)
                    error('SimulinkWiringOptimizer:ModelLoadFailed', ...
                        'モデルの読み込みに失敗しました: %s', modelName);
                end

                obj.currentModel_ = modelBaseName;

                % 出力ディレクトリの準備
                if obj.config_.verbose
                    fprintf('出力ディレクトリ準備中...\n');
                end
                dirSuccess = obj.fileManager_.ensureOutputDirectory();
                result.preprocessing.outputDirectoryReady = dirSuccess;

                % 最適化前の画像保存
                if obj.config_.verbose
                    fprintf('最適化前画像保存中...\n');
                end
                optimizationTarget = obj.getOptimizationTarget(modelBaseName);
                beforeImagePath = obj.fileManager_.generateImagePath(optimizationTarget, 'before');
                imageSuccess = obj.fileManager_.saveModelImage(optimizationTarget, beforeImagePath);
                result.preprocessing.beforeImageSaved = imageSuccess;
                result.preprocessing.beforeImagePath = beforeImagePath;

                if obj.config_.verbose
                    fprintf('前処理完了\n');
                end

            catch ME
                if obj.config_.verbose
                    fprintf('前処理エラー: %s\n', ME.message);
                    fprintf('スタックトレース:\n');
                    for i = 1:length(ME.stack)
                        fprintf('  %s (行 %d)\n', ME.stack(i).name, ME.stack(i).line);
                    end
                end
                error('SimulinkWiringOptimizer:PreprocessingFailed', ...
                    '前処理中にエラーが発生: %s', ME.message);
            end

            % 明示的に戻り値を返す
            result;
        end
        
        function result = analyzeLayout(obj, result)
            % レイアウト分析

            if obj.config_.verbose
                fprintf('\n--- Phase 2: レイアウト分析 ---\n');
            end

            % デバッグ情報を出力
            if obj.config_.verbose
                fprintf('デバッグ: result構造体の確認\n');
                fprintf('  result.preprocessing存在: %s\n', mat2str(isfield(result, 'preprocessing')));
                if isfield(result, 'preprocessing')
                    fprintf('  modelBaseName存在: %s\n', mat2str(isfield(result.preprocessing, 'modelBaseName')));
                    if isfield(result.preprocessing, 'modelBaseName')
                        fprintf('  modelBaseName値: "%s"\n', result.preprocessing.modelBaseName);
                    end
                end
            end

            % 前処理が完了しているかチェック
            if ~isfield(result, 'preprocessing') || ~isfield(result.preprocessing, 'modelBaseName') || isempty(result.preprocessing.modelBaseName)
                error('SimulinkWiringOptimizer:PreprocessingIncomplete', ...
                    '前処理が完了していません。modelBaseNameが設定されていません。');
            end

            optimizationTarget = obj.getOptimizationTarget(result.preprocessing.modelBaseName);
            layoutInfo = obj.layoutAnalyzer_.analyzeLayout(optimizationTarget);

            result.layoutAnalysis.layoutInfo = layoutInfo;
            result.layoutAnalysis.success = true;

            % 明示的に戻り値を返す
            result;
        end
        
        function result = performOptimization(obj, result)
            % 配線最適化の実行
            
            if obj.config_.verbose
                fprintf('\n--- Phase 3: 配線最適化 ---\n');
            end
            
            modelBaseName = result.preprocessing.modelBaseName;
            
            if ~isempty(obj.config_.targetSubsystem)
                % 特定のサブシステムのみを最適化
                obj.wiringOptimizer_.optimizeSubsystemWiring(obj.config_.targetSubsystem);
            else
                % モデル全体の最適化
                obj.wiringOptimizer_.optimizeAllSubsystems(modelBaseName);
            end
            
            % 最適化統計を取得
            result.optimization.stats = obj.wiringOptimizer_.getOptimizationStats();
            result.optimization.success = true;

            % 明示的に戻り値を返す
            result;
        end
        
        function result = evaluateResults(obj, result)
            % 結果の評価
            
            if obj.config_.verbose
                fprintf('\n--- Phase 4: 評価 ---\n');
            end
            
            optimizationTarget = obj.getOptimizationTarget(result.preprocessing.modelBaseName);
            
            % 最適化後の画像保存
            afterImagePath = obj.fileManager_.generateImagePath(optimizationTarget, 'after');
            imageSuccess = obj.fileManager_.saveModelImage(optimizationTarget, afterImagePath);
            result.evaluation.afterImageSaved = imageSuccess;
            result.evaluation.afterImagePath = afterImagePath;
            
            % メトリクス計算
            metrics = obj.evaluator_.calculateMetrics(optimizationTarget);
            result.evaluation.metrics = metrics;
            
            % AI評価（オプション）
            if obj.config_.enableAIEvaluation
                beforeImagePath = result.preprocessing.beforeImagePath;
                aiResult = obj.evaluator_.evaluateWithAI(beforeImagePath, afterImagePath);
                result.evaluation.aiResult = aiResult;
            end

            % レポート生成
            if obj.config_.enableAIEvaluation && isfield(result.evaluation, 'aiResult')
                report = obj.evaluator_.generateReport(metrics, result.evaluation.aiResult);
            else
                report = obj.evaluator_.generateReport(metrics);
            end
            result.evaluation.report = report;
            result.evaluation.success = true;

            % 明示的に戻り値を返す
            result;
        end
        
        function result = postprocessResults(obj, result)
            % 後処理
            
            if obj.config_.verbose
                fprintf('\n--- Phase 5: 後処理 ---\n');
            end
            
            modelBaseName = result.preprocessing.modelBaseName;
            
            % 最適化されたモデルの保存
            timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            saveSuccess = obj.fileManager_.saveOptimizedModel(modelBaseName, ['optimized_', timestamp]);
            result.postprocessing.modelSaved = saveSuccess;
            
            % 比較画像の保存
            optimizationTarget = obj.getOptimizationTarget(modelBaseName);
            obj.evaluator_.saveComparisonImages(optimizationTarget, timestamp);
            
            result.postprocessing.success = true;

            % 明示的に戻り値を返す
            result;
        end
        
        function target = getOptimizationTarget(obj, modelBaseName)
            % 最適化対象を取得
            
            if ~isempty(obj.config_.targetSubsystem)
                target = obj.config_.targetSubsystem;
            else
                target = modelBaseName;
            end
        end
        
        function metrics = getMetrics(obj, systemName)
            % システムのメトリクスを取得
            %
            % 入力:
            %   systemName - システム名（オプション、デフォルトは現在のモデル）
            
            if nargin < 2
                systemName = obj.currentModel_;
            end
            
            if isempty(systemName)
                error('SimulinkWiringOptimizer:NoModel', 'モデルが指定されていません');
            end
            
            metrics = obj.evaluator_.calculateMetrics(systemName);
        end
        
        function updateConfig(obj, varargin)
            % 設定を更新
            %
            % 使用法:
            %   optimizer.updateConfig('preserveLines', false, 'enableAIEvaluation', true)
            
            obj.config_.parseInputArguments(varargin{:});
            
            if obj.config_.verbose
                fprintf('設定を更新しました\n');
                obj.config_.displayConfiguration();
            end
        end
        
        function displayResults(obj, resultIndex)
            % 結果を表示
            %
            % 入力:
            %   resultIndex - 結果のインデックス（オプション、デフォルトは最新）
            
            if isempty(obj.optimizationResults_)
                fprintf('表示する結果がありません\n');
                return;
            end
            
            if nargin < 2
                resultIndex = length(obj.optimizationResults_);
            end
            
            if resultIndex < 1 || resultIndex > length(obj.optimizationResults_)
                error('SimulinkWiringOptimizer:InvalidIndex', '無効な結果インデックス');
            end
            
            result = obj.optimizationResults_(resultIndex);
            
            fprintf('\n=== 最適化結果 #%d ===\n', resultIndex);
            fprintf('モデル: %s\n', result.modelName);
            fprintf('対象: %s\n', obj.getTargetDisplayName(result.targetSubsystem));
            fprintf('開始時刻: %s\n', char(result.startTime));
            fprintf('処理時間: %.2f秒\n', result.elapsedTime);
            fprintf('成功: %s\n', mat2str(result.success));
            
            if result.success && isfield(result.evaluation, 'metrics')
                metrics = result.evaluation.metrics;
                fprintf('\n--- メトリクス ---\n');
                fprintf('信号線数: %d\n', metrics.totalLines);
                fprintf('直線率: %.1f%%\n', metrics.straightLineRatio);
                fprintf('品質スコア: %.1f/100\n', metrics.qualityScore);
                
                if isfield(result.evaluation, 'aiResult') && result.evaluation.aiResult.success
                    fprintf('AIスコア: %d/100\n', result.evaluation.aiResult.score);
                end
            end
            
            if ~result.success
                fprintf('エラー: %s\n', result.error);
            end
            
            fprintf('==================\n');
        end
        
        function name = getTargetDisplayName(~, targetSubsystem)
            % 対象の表示名を取得
            if isempty(targetSubsystem)
                name = 'モデル全体';
            else
                name = targetSubsystem;
            end
        end
        
        function results = getAllResults(obj)
            % 全ての結果を取得
            results = obj.optimizationResults_;
        end
        
        function clearResults(obj)
            % 結果をクリア
            obj.optimizationResults_ = [];
            obj.evaluator_.clearHistory();
            obj.layoutAnalyzer_.clearCache();
            
            if obj.config_.verbose
                fprintf('結果とキャッシュをクリアしました\n');
            end
        end
        
        function cleanup(obj)
            % リソースのクリーンアップ
            obj.fileManager_.cleanup();
            obj.clearResults();
            
            if obj.config_.verbose
                fprintf('クリーンアップ完了\n');
            end
        end
    end
end

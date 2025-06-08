% testOptimization.m - Simulink配線最適化のテストスクリプト
%
% このスクリプトは、配線最適化システムをテストするためのものです。

function testOptimization()
    fprintf('=== Simulink配線最適化テスト ===\n\n');
    
    % テスト対象のモデル
    modelFile = 'fullCarModel.slx';
    
    % モデルファイルの存在確認
    if ~exist(modelFile, 'file')
        error('テストモデルが見つかりません: %s', modelFile);
    end
    
    try
        % テストケースの実行
        runBasicTest(modelFile);
        runAdvancedTest(modelFile);
        runSubsystemTest(modelFile);
        runConfigurationTest(modelFile);
        
        fprintf('\n=== 全テスト完了 ===\n');
        
    catch ME
        fprintf('テスト中にエラーが発生: %s\n', ME.message);
        rethrow(ME);
    end
end

function runBasicTest(modelFile)
    % 基本テスト
    fprintf('--- 基本テスト ---\n');
    
    try
        % デフォルト設定でオプティマイザーを作成
        optimizer = SimulinkWiringOptimizer();
        
        % 最適化実行
        result = optimizer.optimize(modelFile);
        
        % 結果表示
        optimizer.displayResults();
        
        % メトリクス取得
        metrics = optimizer.getMetrics();
        fprintf('取得したメトリクス - 信号線数: %d, 直線率: %.1f%%\n', ...
            metrics.totalLines, metrics.straightLineRatio);
        
        fprintf('基本テスト完了\n\n');
        
    catch ME
        fprintf('基本テストでエラー: %s\n', ME.message);
    end
end

function runAdvancedTest(modelFile)
    % 高度なテスト
    fprintf('--- 高度なテスト ---\n');
    
    try
        % カスタム設定でオプティマイザーを作成
        optimizer = SimulinkWiringOptimizer(...
            'preserveLines', false, ...
            'enableAIEvaluation', true, ...
            'verbose', true, ...
            'wiringParams', struct('baseOffset', 15, 'minSpacing', 20));
        
        % 最適化実行
        result = optimizer.optimize(modelFile);
        
        % 結果の詳細表示
        if result.success
            fprintf('最適化成功 - 処理時間: %.2f秒\n', result.elapsedTime);
            
            if isfield(result.evaluation, 'aiResult') && result.evaluation.aiResult.success
                fprintf('AIスコア: %d/100\n', result.evaluation.aiResult.score);
            end
        else
            fprintf('最適化失敗: %s\n', result.error);
        end
        
        fprintf('高度なテスト完了\n\n');
        
    catch ME
        fprintf('高度なテストでエラー: %s\n', ME.message);
    end
end

function runSubsystemTest(modelFile)
    % サブシステムテスト
    fprintf('--- サブシステムテスト ---\n');
    
    try
        % モデルを読み込んでサブシステムを確認
        [~, modelName, ~] = fileparts(modelFile);
        
        % 一時的にモデルを読み込み
        if ~bdIsLoaded(modelName)
            load_system(modelFile);
            modelLoaded = true;
        else
            modelLoaded = false;
        end
        
        % サブシステムを検索
        subsystems = find_system(modelName, 'BlockType', 'SubSystem');
        
        if ~isempty(subsystems)
            % 最初のサブシステムをテスト
            targetSubsystem = subsystems{1};
            fprintf('テスト対象サブシステム: %s\n', targetSubsystem);
            
            % サブシステム専用オプティマイザーを作成
            optimizer = SimulinkWiringOptimizer('enableAIEvaluation', false, 'verbose', true);
            
            % サブシステムのみを最適化
            result = optimizer.optimizeSubsystem(modelFile, targetSubsystem);
            
            if result.success
                fprintf('サブシステム最適化成功\n');
                optimizer.displayResults();
            else
                fprintf('サブシステム最適化失敗: %s\n', result.error);
            end
        else
            fprintf('サブシステムが見つかりませんでした\n');
        end
        
        % 一時的に読み込んだ場合は閉じる
        if modelLoaded
            close_system(modelName, 0);
        end
        
        fprintf('サブシステムテスト完了\n\n');
        
    catch ME
        fprintf('サブシステムテストでエラー: %s\n', ME.message);
    end
end

function runConfigurationTest(modelFile)
    % 設定テスト
    fprintf('--- 設定テスト ---\n');
    
    try
        % オプティマイザーを作成
        optimizer = SimulinkWiringOptimizer('verbose', false);
        
        % 設定の動的更新テスト
        fprintf('設定更新テスト:\n');
        
        % 設定1: 保守的
        optimizer.updateConfig('preserveLines', true, 'enableAIEvaluation', false, 'verbose', true);
        result1 = optimizer.optimize(modelFile);
        fprintf('  保守的設定 - 成功: %s\n', mat2str(result1.success));

        % 設定2: 積極的
        optimizer.updateConfig('preserveLines', false, 'enableAIEvaluation', false);
        result2 = optimizer.optimize(modelFile);
        fprintf('  積極的設定 - 成功: %s\n', mat2str(result2.success));
        
        % 全結果の表示
        allResults = optimizer.getAllResults();
        fprintf('総実行回数: %d\n', length(allResults));
        
        % 結果の比較
        if length(allResults) >= 2
            compareResults(allResults(end-1), allResults(end));
        end
        
        fprintf('設定テスト完了\n\n');
        
    catch ME
        fprintf('設定テストでエラー: %s\n', ME.message);
    end
end

function compareResults(result1, result2)
    % 結果の比較
    fprintf('\n結果比較:\n');
    
    if result1.success && result2.success
        metrics1 = result1.evaluation.metrics;
        metrics2 = result2.evaluation.metrics;
        
        fprintf('  設定1 - 直線率: %.1f%%, 品質: %.1f\n', ...
            metrics1.straightLineRatio, metrics1.qualityScore);
        fprintf('  設定2 - 直線率: %.1f%%, 品質: %.1f\n', ...
            metrics2.straightLineRatio, metrics2.qualityScore);
        
        if metrics2.qualityScore > metrics1.qualityScore
            fprintf('  → 設定2の方が高品質\n');
        elseif metrics1.qualityScore > metrics2.qualityScore
            fprintf('  → 設定1の方が高品質\n');
        else
            fprintf('  → 品質は同等\n');
        end
    else
        fprintf('  比較できません（一方または両方が失敗）\n');
    end
end

function runPerformanceTest(modelFile)
    % パフォーマンステスト
    fprintf('--- パフォーマンステスト ---\n');
    
    try
        % 複数回実行して平均時間を測定
        numRuns = 3;
        times = zeros(numRuns, 1);
        
        optimizer = SimulinkWiringOptimizer('enableAIEvaluation', false, 'verbose', false);
        
        for i = 1:numRuns
            fprintf('実行 %d/%d...', i, numRuns);
            
            tic;
            result = optimizer.optimize(modelFile);
            times(i) = toc;
            
            if result.success
                fprintf(' 完了 (%.2f秒)\n', times(i));
            else
                fprintf(' 失敗\n');
            end
            
            % 結果をクリア（メモリ節約）
            optimizer.clearResults();
        end
        
        % 統計表示
        avgTime = mean(times);
        stdTime = std(times);
        
        fprintf('\nパフォーマンス統計:\n');
        fprintf('  平均時間: %.2f秒\n', avgTime);
        fprintf('  標準偏差: %.2f秒\n', stdTime);
        fprintf('  最短時間: %.2f秒\n', min(times));
        fprintf('  最長時間: %.2f秒\n', max(times));
        
        fprintf('パフォーマンステスト完了\n\n');
        
    catch ME
        fprintf('パフォーマンステストでエラー: %s\n', ME.message);
    end
end

function runStressTest(modelFile)
    % ストレステスト
    fprintf('--- ストレステスト ---\n');
    
    try
        % 様々な設定での連続実行
        configurations = {
            struct('preserveLines', true, 'enableAIEvaluation', false),
            struct('preserveLines', false, 'enableAIEvaluation', false),
            struct('preserveLines', true, 'enableAIEvaluation', true),
            struct('preserveLines', false, 'enableAIEvaluation', true)
        };
        
        optimizer = SimulinkWiringOptimizer('verbose', false);
        successCount = 0;
        
        for i = 1:length(configurations)
            config = configurations{i};
            fprintf('設定 %d: preserveLines=%s, enableAIEvaluation=%s...', ...
                i, mat2str(config.preserveLines), mat2str(config.enableAIEvaluation));

            try
                optimizer.updateConfig(...
                    'preserveLines', config.preserveLines, ...
                    'enableAIEvaluation', config.enableAIEvaluation);
                
                result = optimizer.optimize(modelFile);
                
                if result.success
                    fprintf(' 成功\n');
                    successCount = successCount + 1;
                else
                    fprintf(' 失敗: %s\n', result.error);
                end
                
            catch ME
                fprintf(' エラー: %s\n', ME.message);
            end
        end
        
        fprintf('\nストレステスト結果: %d/%d 成功\n', successCount, length(configurations));
        fprintf('ストレステスト完了\n\n');
        
    catch ME
        fprintf('ストレステストでエラー: %s\n', ME.message);
    end
end

function showHelp()
    % ヘルプ情報を表示
    fprintf('=== Simulink配線最適化テスト ヘルプ ===\n\n');

    fprintf('使用可能な関数:\n');
    fprintf('  testOptimization()        - 全テストケースを実行\n');
    fprintf('  runBasicTest(modelFile)   - 基本テスト\n');
    fprintf('  runAdvancedTest(modelFile) - 高度なテスト\n');
    fprintf('  runSubsystemTest(modelFile) - サブシステムテスト\n');
    fprintf('  runConfigurationTest(modelFile) - 設定テスト\n');
    fprintf('  runPerformanceTest(modelFile) - パフォーマンステスト\n');
    fprintf('  runStressTest(modelFile)  - ストレステスト\n');
    fprintf('  showHelp()                - このヘルプを表示\n\n');
    
    fprintf('基本的な使用法:\n');
    fprintf('  %% 方法1: 直接実行（簡単）\n');
    fprintf('  optimizer = SimulinkWiringOptimizer(''fullCarModel.slx'');\n\n');

    fprintf('  %% 方法2: 段階的実行（詳細制御）\n');
    fprintf('  optimizer = SimulinkWiringOptimizer();\n');
    fprintf('  result = optimizer.optimize(''fullCarModel.slx'');\n\n');

    fprintf('  %% 結果表示\n');
    fprintf('  optimizer.displayResults();\n\n');

    fprintf('  %% メトリクス取得\n');
    fprintf('  metrics = optimizer.getMetrics();\n\n');

    fprintf('高度な使用法:\n');
    fprintf('  %% カスタム設定\n');
    fprintf('  optimizer = SimulinkWiringOptimizer(''preserveLines'', false, ''enableAIEvaluation'', true);\n\n');

    fprintf('  %% サブシステム最適化\n');
    fprintf('  result = optimizer.optimizeSubsystem(''model.slx'', ''model/subsystem'');\n\n');

    fprintf('  %% 設定の動的更新\n');
    fprintf('  optimizer.updateConfig(''preserveLines'', true);\n\n');
    
    fprintf('注意事項:\n');
    fprintf('  - AI評価機能を使用する場合は OPENAI_API_KEY 環境変数を設定してください\n');
    fprintf('  - テスト前にSimulinkモデルのバックアップを取ることを推奨します\n');
    fprintf('  - 結果は optimization_images フォルダで確認できます\n');
end

% デフォルトでヘルプを表示
if nargout == 0 && nargin == 0
    showHelp();
end

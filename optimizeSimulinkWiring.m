function optimizeSimulinkWiring(modelName, preserveLines, useAI, targetSubsystem)
    % optimizeSimulinkWiring - Simulinkモデルの配線を自動的に最適化する関数
    %
    % 構文:
    %   optimizeSimulinkWiring(modelName, preserveLines)
    %   optimizeSimulinkWiring(modelName, preserveLines, useAI)
    %   optimizeSimulinkWiring(modelName, preserveLines, useAI, targetSubsystem)
    %
    % 入力:
    %   modelName - 最適化するSimulinkモデルのパス
    %   preserveLines - 既存の線を保持するかどうか（オプション、デフォルトはfalse）
    %                   trueの場合、既存の線を削除せずに配線を整理します
    %   useAI - AIによる最適化を使用するかどうか（オプション、デフォルトはfalse）
    %           trueの場合、画像ベースの評価と自動パラメータ調整を行います
    %   targetSubsystem - 特定のサブシステムのみを最適化する場合に指定（オプション）
    %                     指定しない場合はモデル全体を最適化します
    %
    % 説明:
    %   この関数は、人間の配線最適化プロセスを模倣して、Simulinkモデルの配線を
    %   自動的に最適化します。以下のステップで処理を行います：
    %   1. 全体のレイアウトを把握
    %   2. サブシステムごとに配線を整理と最適化
    %   3. 結果の確認と再調整
    %
    % AI最適化モード：
    %   useAI=trueの場合、以下の追加機能が有効になります：
    %   - 画像ベースの評価システムによる配線品質の自動評価
    %   - 複数のパラメータセットを試行して最適なパラメータを自動選択
    %   - 反復的な改善プロセスによる最適化
    %
    %   注意: AI評価を使用するには環境変数 OPENAI_API_KEY を設定する必要があります。
    %   APIキーが設定されていない場合は、自動的に手動評価モードに切り替わります。
    %
    % 人間の配線最適化原則：
    %   1. できるだけ直線的な配線を維持する（垂直・水平の線を優先）
    %   2. 配線の交差を最小限に抑える
    %   3. 近接した配線は上下左右に適切に分散させる
    %   4. 全体的に美しく整理されたレイアウトを実現する
    %   5. サブシステムごとに少しずつ調整する（一度にモデル全体を調整しない）
    %
    % 重要なルール：
    %   - preserveLines=trueの場合、既存の線を削除せずに配線を整理します
    %   - 近接した線は上下左右に移動して重なりを避けます
    %   - 各線の垂直・水平の整列を維持しながら、視覚的な明瞭さを向上させます
    %   - 元の接続は絶対に変更しません（始点と終点は保持）
    %   - 配線の交差を最小限に抑え、全体的に美しいレイアウトを実現します
    %   - サブシステムごとに個別に処理し、階層の異なるサブシステム間のバランスを考慮します
    %
    % 例:
    %   optimizeSimulinkWiring('myModel.slx')
    %   optimizeSimulinkWiring('myModel.slx', true) % 既存の線を保持
    %   optimizeSimulinkWiring('myModel.slx', true, true) % AIによる最適化を使用
    %   optimizeSimulinkWiring('myModel.slx', true, true, 'myModel/subsystem1') % 特定のサブシステムのみを最適化

    % デフォルト値の設定
    if nargin < 2
        preserveLines = false;
    end
    if nargin < 3
        useAI = false;
    end
    if nargin < 4
        targetSubsystem = '';
    end

    % グローバル変数として保存（関数間で共有するため）
    global PRESERVE_EXISTING_LINES;
    global WIRING_PARAMS;
    PRESERVE_EXISTING_LINES = preserveLines;

    % デフォルトのワイヤリングパラメータを設定
    WIRING_PARAMS = struct('baseOffset', 10, 'maxOffset', 50, 'commonXOffset', 50, 'scaleFactor', 0.5);

    % AIモードが有効な場合、APIキーの状態を確認
    if useAI
        % 環境変数からAPIキーを取得
        apiKey = getenv('OPENAI_API_KEY');
        if isempty(apiKey)
            fprintf('注意: OPENAI_API_KEY環境変数が設定されていません。\n');
            fprintf('AIによる自動評価を使用するには、環境変数を設定してください。\n');
            fprintf('APIキーが設定されていない場合は、手動評価モードに切り替わります。\n\n');
        else
            fprintf('OPENAI_API_KEYが設定されています。AIによる自動評価を使用します。\n\n');
        end
    end

    try
        % モデルファイルの存在を確認
        if ~exist(modelName, 'file')
            error('Model file not found: %s', modelName);
        end

        % モデルが既に開かれているか確認
        try
            modelBaseName = get_param(modelName, 'Name');
            fprintf('Model %s is already loaded\n', modelBaseName);
        catch
            % モデルを開く
            fprintf('Loading model %s...\n', modelName);
            hModel = load_system(modelName);
            modelBaseName = get_param(hModel, 'Name');
        end

        % モデルが正しく読み込まれたか確認
        if ~bdIsLoaded(modelBaseName)
            error('Failed to load model: %s', modelName);
        end

        fprintf('Successfully loaded model: %s\n', modelBaseName);

        % AIによる最適化を使用する場合
        if useAI
            fprintf('Using AI-based optimization...\n');

            % 対象システムを設定
            if ~isempty(targetSubsystem)
                % サブシステムの存在を確認
                try
                    % サブシステムのパスを構築
                    if ~contains(targetSubsystem, '/')
                        fullSubsystemPath = [modelBaseName, '/', targetSubsystem];
                    else
                        fullSubsystemPath = targetSubsystem;
                    end

                    % サブシステムの存在を確認
                    try
                        % get_paramを使用してサブシステムの存在を確認
                        get_param(fullSubsystemPath, 'Type');
                    catch
                        error('Subsystem not found: %s', fullSubsystemPath);
                    end

                    fprintf('Subsystem found: %s\n', fullSubsystemPath);
                    optimizationTarget = fullSubsystemPath;
                catch e
                    fprintf('Warning: Error finding subsystem %s: %s\n', targetSubsystem, e.message);
                    fprintf('Falling back to model-level optimization\n');
                    optimizationTarget = modelBaseName;
                end
            else
                % 特定のサブシステムが指定されていない場合は、重要なサブシステムを自動検出
                fprintf('No specific subsystem specified. Detecting important subsystems...\n');
                subsystems = findAllSubsystems(modelBaseName);

                % 重要なサブシステムを検索
                importantSubsystems = {};
                for i = 1:length(subsystems)
                    subsysName = subsystems{i};
                    if contains(subsysName, 'FullVehicle') || contains(subsysName, 'bodyN')
                        importantSubsystems{end+1} = subsysName;
                        fprintf('Found important subsystem: %s\n', subsysName);
                    end
                end

                % 重要なサブシステムが見つかった場合は最初のものを使用
                if ~isempty(importantSubsystems)
                    optimizationTarget = importantSubsystems{1};
                    fprintf('Selected subsystem for optimization: %s\n', optimizationTarget);
                else
                    % 見つからない場合はモデル全体を対象に
                    optimizationTarget = modelBaseName;
                    fprintf('No important subsystems found. Optimizing the entire model.\n');
                end
            end

            % AIによるパラメータ最適化を実行
            fprintf('Starting AI-based parameter optimization for %s...\n', optimizationTarget);
            [bestParams, bestScore] = optimizeWiringParameters(modelBaseName, optimizationTarget);

            % 最適化されたパラメータを適用
            WIRING_PARAMS = bestParams;

            fprintf('Applied AI-optimized parameters: baseOffset=%.1f, maxOffset=%.1f, commonXOffset=%.1f, scaleFactor=%.2f\n', ...
                WIRING_PARAMS.baseOffset, WIRING_PARAMS.maxOffset, WIRING_PARAMS.commonXOffset, WIRING_PARAMS.scaleFactor);

            % 特定のサブシステムのみを最適化する場合は終了
            if ~isempty(targetSubsystem)
                fprintf('Optimization of specific subsystem completed: %s\n', targetSubsystem);

                % 最適化されたモデルを保存
                try
                    % モデル名から拡張子を除去（拡張子がある場合）
                    [filepath, name, ext] = fileparts(modelName);
                    if isempty(ext)
                        ext = '.slx';  % デフォルトの拡張子
                    end

                    % モデルベース名を取得
                    modelBaseName = name;

                    % モデルが読み込まれているか確認
                    if ~bdIsLoaded(modelBaseName)
                        fprintf('Warning: Model %s is not loaded, cannot save optimized version\n', modelBaseName);
                    else
                        % タイムスタンプを生成
                        dt = datetime('now');
                        timestamp = sprintf('%04d%02d%02d_%02d%02d%02d', ...
                            dt.Year, dt.Month, dt.Day, dt.Hour, dt.Minute, round(dt.Second));

                        % 新しいファイル名を生成
                        newFileName = fullfile(filepath, sprintf('%s_%s_AI_optimized%s', name, timestamp, ext));

                        % モデルを保存
                        fprintf('Saving optimized model as: %s\n', newFileName);
                        save_system(modelBaseName, newFileName);
                        fprintf('AI-optimized model saved as: %s\n', newFileName);
                    end
                catch e
                    fprintf('Warning: Error saving optimized model: %s\n', e.message);
                end

                return;
            end
        end

        % 既存の線を保持するモードの場合、メッセージを表示
        if PRESERVE_EXISTING_LINES
            fprintf('Running in preserve mode: Existing lines will not be deleted\n');
        end

        % 画像出力用のフォルダを作成
        outputDir = 'optimization_images';
        if ~exist(outputDir, 'dir')
            mkdir(outputDir);
        end

        % モデル内の全配線を最適化
        fprintf('Starting wiring optimization for model: %s\n', modelBaseName);

        % 最適化前の画像を保存
        try
            fprintf('Saving before-optimization image...\n');
            saveModelImage(modelBaseName, fullfile(outputDir, [modelBaseName, '_before.png']));
        catch e
            fprintf('Warning: Could not save before image: %s\n', e.message);
        end

        % ステップ1: 全体のレイアウトを把握
        fprintf('Step 1: Analyzing overall layout...\n');
        [blockInfo, signalFlowInfo] = analyzeModelLayout(modelBaseName);

        % ステップ2: ポート位置の微調整（特例的な処理のため省略）
        fprintf('Step 2: Port position adjustment skipped (special case processing not needed)...\n');

        % ステップ3: サブシステムごとに配線の整理
        fprintf('Step 3: Organizing wires subsystem by subsystem...\n');

        % サブシステムを取得
        allSystems = find_system(modelBaseName, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', 'SubSystem');
        fprintf('  - Found %d subsystems to process\n', length(allSystems));

        % 各サブシステムを個別に処理
        for i = 1:length(allSystems)
            currentSystem = allSystems{i};
            fprintf('  - Processing subsystem %d/%d: %s\n', i, length(allSystems), currentSystem);

            % 各サブシステムに対して配線を最適化
            optimizeSubsystemWiring(currentSystem, preserveLines);

            % 処理の進捗状況を表示（10%ごと）
            if mod(i, max(1, round(length(allSystems)/10))) == 0
                fprintf('    Progress: %d%% complete\n', round(i/length(allSystems)*100));
            end
        end

        % 最後にトップレベルの配線を最適化
        fprintf('  - Processing top-level system: %s\n', modelBaseName);
        optimizeSubsystemWiring(modelBaseName, preserveLines);

        % ステップ4: 結果の確認と再調整
        fprintf('Step 4: Verifying and readjusting...\n');
        verifyAndReadjust(modelBaseName);

        % 最適化後の画像を保存
        try
            fprintf('Saving after-optimization image...\n');
            saveModelImage(modelBaseName, fullfile(outputDir, [modelBaseName, '_after.png']));

            % 重要なサブシステムの画像も保存
            subsystems = findAllSubsystems(modelBaseName);
            for i = 1:length(subsystems)
                subsysName = subsystems{i};
                if contains(subsysName, 'FullVehicle') || contains(subsysName, 'bodyN')
                    [~, shortName] = fileparts(subsysName);
                    fprintf('Saving after image for key subsystem: %s\n', shortName);
                    saveModelImage(subsysName, fullfile(outputDir, [shortName, '_after.png']));
                end
            end
        catch e
            fprintf('Warning: Could not save after image: %s\n', e.message);
        end

        % 現在の日時を取得して新しいファイル名を生成
        [filepath, name, ext] = fileparts(modelName);
        dt = datetime('now');
        timestamp = sprintf('%04d%02d%02d_%02d%02d%02d', ...
            dt.Year, dt.Month, dt.Day, dt.Hour, dt.Minute, round(dt.Second));
        newFileName = fullfile(filepath, sprintf('%s_%s%s', name, timestamp, ext));

        % 変更を新しいファイルとして保存
        save_system(modelBaseName, newFileName);
        fprintf('Optimized model saved as: %s\n', newFileName);
        fprintf('Before and after images saved in the "%s" directory.\n', outputDir);

        % 最適化の品質メトリクスを表示
        displayOptimizationMetrics(modelBaseName);

    catch e
        fprintf('Error: %s\n', e.message);
        fprintf('Stack trace: %s\n', getReport(e, 'extended'));
    end
end

function [blockInfo, signalFlowInfo] = analyzeModelLayout(modelName)
    % モデルの全体的なレイアウトを分析し、ブロックの配置と信号の流れを把握する

    fprintf('Analyzing block placement and signal flow...\n');

    % ブロック情報を収集
    allBlocks = find_system(modelName, 'LookUnderMasks', 'all', 'FollowLinks', 'on');
    blockInfo = struct('Blocks', {allBlocks}, 'Count', length(allBlocks));
    fprintf('Found %d blocks in the model\n', blockInfo.Count);

    % 信号の流れを分析
    allLines = find_system(modelName, 'FindAll', 'on', 'Type', 'Line');
    signalFlowInfo = struct('Lines', {allLines}, 'Count', length(allLines));
    fprintf('Found %d signal lines in the model\n', signalFlowInfo.Count);

    % 特定のブロックの位置関係を分析
    specialBlocks = {'c_alfa', 'reff', 'delta', 'yVelo', 'Lf', 'yawRate'};
    specialBlocksInfo = cell(length(specialBlocks), 1);

    for i = 1:length(specialBlocks)
        blockName = specialBlocks{i};
        blocks = find_system(modelName, 'FollowLinks', 'on', 'LookUnderMasks', 'all', 'Name', blockName);

        if ~isempty(blocks)
            positions = zeros(length(blocks), 4);
            for j = 1:length(blocks)
                positions(j, :) = get_param(blocks{j}, 'Position');
            end

            specialBlocksInfo{i} = struct('Name', blockName, 'Blocks', {blocks}, 'Positions', positions);
            fprintf('Analyzed special block: %s (%d instances)\n', blockName, length(blocks));
        end
    end

    % 特定のブロック情報を追加
    blockInfo.SpecialBlocks = specialBlocksInfo;

    % 信号の流れの方向を分析
    try
        % 左から右への信号の流れが主流かどうかを確認
        leftToRightCount = 0;
        otherDirectionCount = 0;

        for i = 1:length(allLines)
            try
                line = allLines(i);
                srcPort = get_param(line, 'SrcPortHandle');
                dstPorts = get_param(line, 'DstPortHandle');

                if srcPort ~= -1 && ~isempty(dstPorts) && dstPorts(1) ~= -1
                    srcPos = get_param(srcPort, 'Position');
                    dstPos = get_param(dstPorts(1), 'Position');

                    if srcPos(1) < dstPos(1)  % 左から右への信号
                        leftToRightCount = leftToRightCount + 1;
                    else
                        otherDirectionCount = otherDirectionCount + 1;
                    end
                end
            catch
                continue;
            end
        end

        signalFlowInfo.LeftToRightRatio = leftToRightCount / max(1, leftToRightCount + otherDirectionCount);
        fprintf('Signal flow analysis: %.1f%% of signals flow from left to right\n', ...
            signalFlowInfo.LeftToRightRatio * 100);
    catch e
        fprintf('Warning: Error during signal flow direction analysis: %s\n', e.message);
    end

    return;
end



function verifyAndReadjust(modelName)
    % 最適化結果を検証し、必要に応じて再調整する
    % 人間の配線最適化原則に基づいて配線を整理：
    % 1. できるだけ直線的な配線を維持する（垂直・水平の線を優先）
    % 2. 配線の交差を最小限に抑える
    % 3. 全体的に美しく整理されたレイアウトを実現する

    global PRESERVE_EXISTING_LINES;

    fprintf('Verifying optimization results...\n');

    % 交差する配線の数をカウント
    try
        allLines = find_system(modelName, 'FindAll', 'on', 'Type', 'Line');

        % 交差チェックは複雑なため、簡易的な推定を行う
        fprintf('Checking for potential line crossings...\n');

        % 各ラインのポイントを取得
        linePoints = cell(length(allLines), 1);
        lineHandles = zeros(length(allLines), 1);
        validLineCount = 0;

        for i = 1:length(allLines)
            try
                if ishandle(allLines(i))
                    linePoints{i} = get_param(allLines(i), 'Points');
                    lineHandles(i) = allLines(i);
                    validLineCount = validLineCount + 1;
                end
            catch
                linePoints{i} = [];
                lineHandles(i) = -1;
            end
        end

        % 潜在的な交差の数を推定
        potentialCrossings = 0;
        crossingPairs = [];

        for i = 1:length(linePoints)
            for j = i+1:length(linePoints)
                if ~isempty(linePoints{i}) && ~isempty(linePoints{j}) && lineHandles(i) > 0 && lineHandles(j) > 0
                    % 2つのラインのバウンディングボックスが重なっているかチェック
                    iMinX = min(linePoints{i}(:,1));
                    iMaxX = max(linePoints{i}(:,1));
                    iMinY = min(linePoints{i}(:,2));
                    iMaxY = max(linePoints{i}(:,2));

                    jMinX = min(linePoints{j}(:,1));
                    jMaxX = max(linePoints{j}(:,1));
                    jMinY = min(linePoints{j}(:,2));
                    jMaxY = max(linePoints{j}(:,2));

                    % バウンディングボックスが重なっている場合、潜在的な交差としてカウント
                    if iMinX <= jMaxX && iMaxX >= jMinX && iMinY <= jMaxY && iMaxY >= jMinY
                        potentialCrossings = potentialCrossings + 1;
                        crossingPairs = [crossingPairs; i j];
                    end
                end
            end
        end

        fprintf('Found approximately %d potential line crossings\n', potentialCrossings);

        % 交差が多い場合は再調整
        if potentialCrossings > 5
            fprintf('High number of potential crossings detected. Performing readjustment...\n');

            % 既存の線を保持するモードの場合
            if PRESERVE_EXISTING_LINES
                fprintf('Adjusting lines to minimize crossings while preserving connections...\n');

                % 交差している配線ペアを優先的に調整
                for k = 1:min(size(crossingPairs, 1), 10)  % 最大10ペアまで処理
                    i = crossingPairs(k, 1);
                    j = crossingPairs(k, 2);

                    if lineHandles(i) > 0 && lineHandles(j) > 0
                        try
                            % 交差している配線ペアを調整
                            adjustCrossingLines(lineHandles(i), lineHandles(j), linePoints{i}, linePoints{j});
                        catch e
                            fprintf('Warning: Error adjusting crossing lines: %s\n', e.message);
                        end
                    end
                end

                % 残りの配線も必要に応じて調整
                for i = 1:length(allLines)
                    if ishandle(allLines(i))
                        try
                            % 配線の特性を分析
                            points = get_param(allLines(i), 'Points');

                            % 配線の複雑さを評価
                            if size(points, 1) > 5
                                % 複雑な配線は単純化
                                simplifiedPoints = simplifyLinePoints(points);
                                set_param(allLines(i), 'Points', simplifiedPoints);
                            end
                        catch
                            % エラーが発生しても続行
                        end
                    end
                end
            else
                % 既存の線を保持しないモードの場合は自動配線を再適用
                fprintf('Re-optimizing branch points...\n');
                for i = 1:length(allLines)
                    if ishandle(allLines(i))
                        try
                            % 自動配線を再適用
                            set_param(allLines(i), 'autorouting', 'on');
                        catch
                            % エラーが発生しても続行
                        end
                    end
                end
            end
        else
            fprintf('Line crossing check passed. No readjustment needed.\n');
        end

        % 最終的な品質メトリクスを計算
        straightSegments = 0;
        diagonalSegments = 0;
        totalSegments = 0;

        for i = 1:length(allLines)
            try
                if ishandle(allLines(i))
                    points = get_param(allLines(i), 'Points');

                    for j = 1:size(points, 1)-1
                        p1 = points(j, :);
                        p2 = points(j+1, :);

                        % 垂直または水平のセグメント
                        if p1(1) == p2(1) || p1(2) == p2(2)
                            straightSegments = straightSegments + 1;
                        else
                            diagonalSegments = diagonalSegments + 1;
                        end

                        totalSegments = totalSegments + 1;
                    end
                end
            catch
                continue;
            end
        end

        if totalSegments > 0
            straightRatio = straightSegments / totalSegments * 100;
            fprintf('Final quality metrics: %.1f%% straight segments (vertical/horizontal)\n', straightRatio);
        end

    catch e
        fprintf('Warning: Error during verification: %s\n', e.message);
    end
end

function adjustCrossingLines(line1Handle, line2Handle, points1, points2)
    % 交差している2つの配線を調整して交差を減らす

    try
        % 配線1の特性を分析
        srcPort1 = get_param(line1Handle, 'SrcPortHandle');
        if srcPort1 == -1
            return;
        end

        % 配線2の特性を分析
        srcPort2 = get_param(line2Handle, 'SrcPortHandle');
        if srcPort2 == -1
            return;
        end

        % ソースポートの位置を取得
        srcPos1 = get_param(srcPort1, 'Position');
        srcPos2 = get_param(srcPort2, 'Position');

        % ポート番号を取得
        srcPortNumber1 = get_param(srcPort1, 'PortNumber');
        srcPortNumber2 = get_param(srcPort2, 'PortNumber');

        % 配線の方向を分析
        isHorizontal1 = isHorizontalDominant(points1);
        isHorizontal2 = isHorizontalDominant(points2);

        % 交差を避けるための調整方法を決定
        if isHorizontal1 && isHorizontal2
            % 両方が水平方向主体の場合、垂直方向にオフセット
            if srcPortNumber1 < srcPortNumber2
                % 配線1を上に、配線2を下に移動
                adjustedPoints1 = adjustLinePoints(points1, 0, -25);
                adjustedPoints2 = adjustLinePoints(points2, 0, 25);
            else
                % 配線1を下に、配線2を上に移動
                adjustedPoints1 = adjustLinePoints(points1, 0, 25);
                adjustedPoints2 = adjustLinePoints(points2, 0, -25);
            end
        elseif ~isHorizontal1 && ~isHorizontal2
            % 両方が垂直方向主体の場合、水平方向にオフセット
            if srcPortNumber1 < srcPortNumber2
                % 配線1を左に、配線2を右に移動
                adjustedPoints1 = adjustLinePoints(points1, -25, 0);
                adjustedPoints2 = adjustLinePoints(points2, 25, 0);
            else
                % 配線1を右に、配線2を左に移動
                adjustedPoints1 = adjustLinePoints(points1, 25, 0);
                adjustedPoints2 = adjustLinePoints(points2, -25, 0);
            end
        else
            % 一方が水平、もう一方が垂直の場合
            if isHorizontal1
                % 配線1が水平主体の場合、垂直方向にオフセット
                adjustedPoints1 = adjustLinePoints(points1, 0, -20);
                % 配線2が垂直主体の場合、水平方向にオフセット
                adjustedPoints2 = adjustLinePoints(points2, 20, 0);
            else
                % 配線1が垂直主体の場合、水平方向にオフセット
                adjustedPoints1 = adjustLinePoints(points1, 20, 0);
                % 配線2が水平主体の場合、垂直方向にオフセット
                adjustedPoints2 = adjustLinePoints(points2, 0, -20);
            end
        end

        % 調整した配線を適用
        set_param(line1Handle, 'Points', adjustedPoints1);
        set_param(line2Handle, 'Points', adjustedPoints2);

        fprintf('Adjusted crossing lines to minimize intersection\n');
    catch e
        fprintf('Error adjusting crossing lines: %s\n', e.message);
    end
end

function isHorizontal = isHorizontalDominant(points)
    % 配線が水平方向主体かどうかを判定

    if size(points, 1) < 2
        isHorizontal = true;
        return;
    end

    % 始点と終点の位置
    startPoint = points(1, :);
    endPoint = points(end, :);

    % 水平方向と垂直方向の変化量
    horizontalLength = abs(endPoint(1) - startPoint(1));
    verticalLength = abs(endPoint(2) - startPoint(2));

    % 水平方向の変化が大きい場合は水平方向主体
    isHorizontal = horizontalLength >= verticalLength;
end

function points = simplifyLinePoints(points)
    % 複雑な配線を単純化する

    % 始点と終点を保存
    startPoint = points(1, :);
    endPoint = points(end, :);

    % 配線の方向を分析
    isHorizontal = isHorizontalDominant(points);

    % 単純化した配線を生成
    if isHorizontal
        % 水平方向主体の場合
        % できるだけ直線的な配線を生成（最小限のポイント数）
        if abs(startPoint(2) - endPoint(2)) < 10
            % 始点と終点がほぼ同じ高さの場合は完全な直線
            simplifiedPoints = [
                startPoint;
                endPoint
            ];
        else
            % 高さが異なる場合は1つの折れ点で直線的に
            simplifiedPoints = [
                startPoint;
                endPoint(1), startPoint(2);
                endPoint
            ];
        end
    else
        % 垂直方向主体の場合
        % できるだけ直線的な配線を生成（最小限のポイント数）
        if abs(startPoint(1) - endPoint(1)) < 10
            % 始点と終点がほぼ同じX座標の場合は完全な直線
            simplifiedPoints = [
                startPoint;
                endPoint
            ];
        else
            % X座標が異なる場合は1つの折れ点で直線的に
            simplifiedPoints = [
                startPoint;
                startPoint(1), endPoint(2);
                endPoint
            ];
        end
    end

    % 冗長なポイントを削除
    points = removeRedundantPoints(simplifiedPoints);
end

function points = straightenLine(points)
    % 配線をできるだけ一直線にする関数

    % 始点と終点を保存
    startPoint = points(1, :);
    endPoint = points(end, :);

    % ポイント数が少ない場合は既に直線的と判断
    if size(points, 1) <= 3
        return;
    end

    % 配線の方向を分析
    horizontalLength = abs(endPoint(1) - startPoint(1));
    verticalLength = abs(endPoint(2) - startPoint(2));

    % 直線化した配線を生成
    if horizontalLength >= verticalLength
        % 水平方向主体の場合
        if verticalLength < 5
            % ほぼ水平な場合は完全な直線
            points = [startPoint; endPoint];
        else
            % 高さの差がある場合は最小限の折れ点で直線的に
            midX = (startPoint(1) + endPoint(1)) / 2;
            points = [
                startPoint;
                midX, startPoint(2);
                midX, endPoint(2);
                endPoint
            ];
        end
    else
        % 垂直方向主体の場合
        if horizontalLength < 5
            % ほぼ垂直な場合は完全な直線
            points = [startPoint; endPoint];
        else
            % 幅の差がある場合は最小限の折れ点で直線的に
            midY = (startPoint(2) + endPoint(2)) / 2;
            points = [
                startPoint;
                startPoint(1), midY;
                endPoint(1), midY;
                endPoint
            ];
        end
    end

    % 冗長なポイントを削除して最終的な直線化
    points = removeRedundantPoints(points);
end

function displayOptimizationMetrics(modelName)
    % 最適化の品質メトリクスを表示

    fprintf('\nOptimization Quality Metrics:\n');

    try
        % 配線の総数
        allLines = find_system(modelName, 'FindAll', 'on', 'Type', 'Line');
        fprintf('Total number of wires: %d\n', length(allLines));

        % 垂直・水平セグメントの比率を計算
        straightSegments = 0;
        diagonalSegments = 0;

        for i = 1:length(allLines)
            try
                if ishandle(allLines(i))
                    points = get_param(allLines(i), 'Points');

                    for j = 1:size(points, 1)-1
                        p1 = points(j, :);
                        p2 = points(j+1, :);

                        % 垂直または水平のセグメント
                        if p1(1) == p2(1) || p1(2) == p2(2)
                            straightSegments = straightSegments + 1;
                        else
                            diagonalSegments = diagonalSegments + 1;
                        end
                    end
                end
            catch
                continue;
            end
        end

        totalSegments = straightSegments + diagonalSegments;
        if totalSegments > 0
            straightRatio = straightSegments / totalSegments * 100;
            fprintf('Straight segments (vertical/horizontal): %.1f%%\n', straightRatio);
        end

        % 分岐点の数を推定
        branchPoints = 0;
        for i = 1:length(allLines)
            try
                if ishandle(allLines(i))
                    dstPorts = get_param(allLines(i), 'DstPortHandle');
                    if length(dstPorts) > 1
                        branchPoints = branchPoints + length(dstPorts) - 1;
                    end
                end
            catch
                continue;
            end
        end

        fprintf('Estimated number of branch points: %d\n', branchPoints);

        % 平均配線長を計算
        totalLength = 0;
        validLines = 0;

        for i = 1:length(allLines)
            try
                if ishandle(allLines(i))
                    points = get_param(allLines(i), 'Points');

                    % 配線の長さを計算
                    lineLength = 0;
                    for j = 1:size(points, 1)-1
                        p1 = points(j, :);
                        p2 = points(j+1, :);
                        segmentLength = sqrt((p2(1) - p1(1))^2 + (p2(2) - p1(2))^2);
                        lineLength = lineLength + segmentLength;
                    end

                    totalLength = totalLength + lineLength;
                    validLines = validLines + 1;
                end
            catch
                continue;
            end
        end

        if validLines > 0
            avgLength = totalLength / validLines;
            fprintf('Average wire length: %.1f pixels\n', avgLength);
        end

    catch e
        fprintf('Warning: Error calculating metrics: %s\n', e.message);
    end

    fprintf('\nOptimization complete. The model has been optimized according to human-like wiring patterns.\n');
end





function points = adjustLinePoints(points, offsetX, offsetY)
    % 線のポイントを指定された方向に移動する関数
    % 入力:
    %   points - 線のポイント配列
    %   offsetX - X方向のオフセット（正の値で右に移動、負の値で左に移動）
    %   offsetY - Y方向のオフセット（正の値で下に移動、負の値で上に移動）

    % 始点と終点を保存（元の接続を維持するため）
    startPoint = points(1,:);
    endPoint = points(end,:);

    % 配線の特性を分析
    lineLength = size(points, 1);

    % 配線の方向を分析
    horizontalLength = abs(endPoint(1) - startPoint(1));
    verticalLength = abs(endPoint(2) - startPoint(2));
    isHorizontalDominant = horizontalLength > verticalLength;

    % オフセットの大きさに基づいて処理方法を決定
    if abs(offsetX) >= 50 || abs(offsetY) >= 50
        % 大きなオフセットの場合は、より洗練された配線パターンを生成

        % 配線の方向に基づいて最適な分岐点を設定
        if isHorizontalDominant
            % 水平方向が主要な場合

            % 始点から少し離れた位置に最初の分岐点を設定
            firstBranchX = startPoint(1) + 30;
            firstBranchY = startPoint(2);

            % 終点の少し手前に最後の分岐点を設定
            lastBranchX = endPoint(1) - 30;
            lastBranchY = endPoint(2);

            % メインの垂直ラインの位置を設定（オフセットを適用）
            mainLineX = startPoint(1) + offsetX;

            % 新しい配線パターンを生成
            newPoints = [
                startPoint;                  % 始点
                firstBranchX, firstBranchY;  % 最初の分岐点
                mainLineX, firstBranchY;     % メイン垂直ラインへの接続点
                mainLineX, lastBranchY;      % メイン垂直ラインから終点方向への接続点
                lastBranchX, lastBranchY;    % 最後の分岐点
                endPoint                     % 終点
            ];
        else
            % 垂直方向が主要な場合

            % 始点から少し離れた位置に最初の分岐点を設定
            firstBranchX = startPoint(1);
            firstBranchY = startPoint(2) + 30;

            % 終点の少し手前に最後の分岐点を設定
            lastBranchX = endPoint(1);
            lastBranchY = endPoint(2) - 30;

            % メインの水平ラインの位置を設定（オフセットを適用）
            mainLineY = startPoint(2) + offsetY;

            % 新しい配線パターンを生成
            newPoints = [
                startPoint;                  % 始点
                firstBranchX, firstBranchY;  % 最初の分岐点
                firstBranchX, mainLineY;     % メイン水平ラインへの接続点
                lastBranchX, mainLineY;      % メイン水平ラインから終点方向への接続点
                lastBranchX, lastBranchY;    % 最後の分岐点
                endPoint                     % 終点
            ];
        end

        points = newPoints;
    elseif abs(offsetX) >= 20 || abs(offsetY) >= 20
        % 中程度のオフセットの場合は、適度に洗練された配線パターンを生成

        % 配線の方向に基づいて最適な分岐点を設定
        if isHorizontalDominant
            % 水平方向が主要な場合

            % 中間点を計算
            midX = (startPoint(1) + endPoint(1)) / 2;

            % オフセットを適用した中間点
            offsetMidY = startPoint(2) + offsetY;

            % 新しい配線パターンを生成
            newPoints = [
                startPoint;              % 始点
                midX, startPoint(2);     % 水平移動
                midX, offsetMidY;        % 垂直移動（オフセット適用）
                midX, endPoint(2);       % 垂直移動
                endPoint                 % 終点
            ];
        else
            % 垂直方向が主要な場合

            % 中間点を計算
            midY = (startPoint(2) + endPoint(2)) / 2;

            % オフセットを適用した中間点
            offsetMidX = startPoint(1) + offsetX;

            % 新しい配線パターンを生成
            newPoints = [
                startPoint;              % 始点
                startPoint(1), midY;     % 垂直移動
                offsetMidX, midY;        % 水平移動（オフセット適用）
                endPoint(1), midY;       % 水平移動
                endPoint                 % 終点
            ];
        end

        points = newPoints;
    else
        % 通常の小さなオフセットの場合は元の処理を適用

        % 中間点のみを移動
        if size(points, 1) > 2
            % 中間点のX座標を指定されたオフセット分だけ移動
            points(2:end-1,1) = points(2:end-1,1) + offsetX;

            % 中間点のY座標を指定されたオフセット分だけ移動
            points(2:end-1,2) = points(2:end-1,2) + offsetY;
        else
            % ポイントが2つしかない場合は、中間点を追加してオフセットを適用
            midPoint = (startPoint + endPoint) / 2;
            midPoint(1) = midPoint(1) + offsetX;
            midPoint(2) = midPoint(2) + offsetY;

            points = [startPoint; midPoint; endPoint];
        end
    end

    % 始点と終点を元に戻す（元の接続を絶対に変更しない）
    points(1,:) = startPoint;
    points(end,:) = endPoint;

    % 垂直・水平の整列を維持するために冗長なポイントを削除
    points = removeRedundantPoints(points);
end

function points = adjustLinePointsToRight(points, offsetX)
    % 線のポイントを右側に移動する関数（後方互換性のため維持）
    % 入力:
    %   points - 線のポイント配列
    %   offsetX - X方向のオフセット（正の値で右に移動）

    % 新しい関数を使用
    points = adjustLinePoints(points, offsetX, 0);
end

function points = optimizeLinePoints(points, srcPos, dstInfo)
    % 既存の線のポイントを最適化する関数
    % 入力:
    %   points - 既存の線のポイント配列
    %   srcPos - ソースポートの位置
    %   dstInfo - デスティネーション情報

    % 線の始点と終点を保持（元の接続を絶対に変更しない）
    startPoint = points(1,:);
    endPoint = points(end,:);

    % 線の中間部分を最適化
    if size(points, 1) > 2
        % 主要な分岐点の位置を計算
        mainBranchX = srcPos(1) + 50;  % ソースから50ピクセル右

        % デスティネーションの位置を取得
        dstPos = [];
        for i = 1:length(dstInfo)
            if ~isempty(dstInfo{i})
                dstPos = dstInfo{i}.Position(1:2);
                break;
            end
        end

        if ~isempty(dstPos)
            % 最適化されたポイントを生成
            % 始点と終点は元のまま保持し、中間点のみを最適化
            newPoints = [
                startPoint;  % 元の始点を保持
                mainBranchX, startPoint(2);  % 最初の分岐点
                mainBranchX, endPoint(2);    % 2番目の分岐点
                endPoint     % 元の終点を保持
            ];

            % 不要な点を削除
            points = removeRedundantPoints(newPoints);

            % 始点と終点が変わっていないか確認（安全対策）
            if ~isequal(points(1,:), startPoint) || ~isequal(points(end,:), endPoint)
                % 始点または終点が変わっている場合は強制的に元に戻す
                points(1,:) = startPoint;
                points(end,:) = endPoint;
                fprintf('Warning: Start or end point was modified. Restored to original position.\n');
            end
        end
    end

    return;
end







function optimizeSubsystemWiring(subsystemName, preserveLines)
    % サブシステムごとに配線を最適化する関数
    % 人間の配線最適化原則に基づいて配線を整理：
    % 1. できるだけ直線的な配線を維持する（垂直・水平の線を優先）
    % 2. 配線の交差を最小限に抑える
    % 3. 近接した配線は上下左右に適切に分散させる
    % 4. 全体的に美しく整理されたレイアウトを実現する
    % 5. サブシステム入力ポート手前では配線を垂直に揃え、適切に間隔を空ける

    try
        % システム内の全ラインを取得
        lines = find_system(subsystemName, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'Line');

        if isempty(lines)
            fprintf('  - No lines found in %s\n', subsystemName);
            return;
        end

        fprintf('  - Found %d lines in %s\n', length(lines), subsystemName);

        % サブシステムへの入力配線を特定
        subsystemInputLines = identifySubsystemInputLines(subsystemName, lines);
        fprintf('  - Found %d lines connecting to subsystem inputs\n', length(subsystemInputLines));

        % 既存の線を保持するモードの場合
        if preserveLines
            fprintf('  - Preserving existing lines while optimizing...\n');

            % サブシステムへの入力配線を最優先で特別に処理
            if ~isempty(subsystemInputLines)
                fprintf('  - Prioritizing subsystem input lines optimization...\n');

                % 自動配線を無効化して手動で配線を設定
                for j = 1:length(subsystemInputLines)
                    try
                        lineHandle = subsystemInputLines(j);
                        % 自動配線を無効化
                        try
                            set_param(lineHandle, 'autorouting', 'off');
                        catch
                            % 自動配線パラメータがない場合は無視
                        end
                    catch
                        % エラーが発生しても続行
                    end
                end

                % サブシステム入力配線を特別に処理
                optimizeSubsystemInputLines(subsystemInputLines);

                % 変更を確実に反映させるために少し待機
                pause(0.1);
            end

            % 各ラインを個別に処理（サブシステム入力配線以外）
            for j = 1:length(lines)
                try
                    lineHandle = lines(j);

                    % サブシステム入力配線は既に処理済みならスキップ
                    if ismember(lineHandle, subsystemInputLines)
                        continue;
                    end

                    % ソースポートを取得
                    srcPort = get_param(lineHandle, 'SrcPortHandle');
                    if srcPort == -1
                        continue;
                    end

                    % ソースブロックを取得
                    sourceBlock = get_param(srcPort, 'Parent');

                    % ポート番号を取得
                    srcPortNumber = get_param(srcPort, 'PortNumber');
                    portNumberStr = num2str(srcPortNumber);

                    % 既存の線のポイントを取得
                    existingPoints = get_param(lineHandle, 'Points');

                    % 配線の特性を分析
                    lineLength = size(existingPoints, 1);

                    % 配線の複雑さを評価（ポイント数が多いほど複雑）
                    isComplexLine = lineLength > 4;

                    % ポート番号に基づく分類（近接しやすいポートを特定）
                    isHighNumberPort = srcPortNumber >= 8;

                    % 配線の方向を分析
                    if lineLength >= 2
                        startX = existingPoints(1, 1);
                        endX = existingPoints(end, 1);
                        startY = existingPoints(1, 2);
                        endY = existingPoints(end, 2);

                        % 水平方向の長さ
                        horizontalLength = abs(endX - startX);
                        % 垂直方向の長さ
                        verticalLength = abs(endY - startY);

                        % 配線の主な方向を判定
                        isHorizontalDominant = horizontalLength > verticalLength;
                    else
                        isHorizontalDominant = true; % デフォルト
                    end

                    % 配線の特性に基づいて調整方法を決定
                    if isComplexLine && isHighNumberPort
                        % 複雑な配線で高いポート番号の場合は大きくオフセット
                        % 配線の方向に基づいて適切な方向にオフセット
                        if isHorizontalDominant
                            % 水平方向が主要な場合は垂直方向にオフセット
                            % ポート番号の偶数/奇数で上下を分ける
                            if mod(srcPortNumber, 2) == 0
                                adjustedPoints = adjustLinePoints(existingPoints, 0, -40); % 上方向
                            else
                                adjustedPoints = adjustLinePoints(existingPoints, 0, 40);  % 下方向
                            end
                        else
                            % 垂直方向が主要な場合は水平方向にオフセット
                            % ポート番号の偶数/奇数で左右を分ける
                            if mod(srcPortNumber, 2) == 0
                                adjustedPoints = adjustLinePoints(existingPoints, -40, 0); % 左方向
                            else
                                adjustedPoints = adjustLinePoints(existingPoints, 40, 0);  % 右方向
                            end
                        end

                        % 線のポイントを更新（既存の線を保持したまま位置を調整）
                        set_param(lineHandle, 'Points', adjustedPoints);

                        % 配線の直線性を高めるための追加処理
                        try
                            % 現在の配線ポイントを取得
                            currentPoints = get_param(lineHandle, 'Points');

                            % 配線をより直線的にするために冗長なポイントを削除
                            straightenedPoints = straightenLine(currentPoints);

                            % 直線化した配線を適用
                            set_param(lineHandle, 'Points', straightenedPoints);
                        catch
                            % エラーが発生しても続行
                        end
                    elseif isHighNumberPort
                        % 高いポート番号の場合は中程度のオフセット
                        % ポート番号に基づいて異なる方向に移動（上下左右に分散）
                        % 4方向に分散させるためにポート番号を4で割った余りを使用
                        remainder = mod(srcPortNumber, 4);

                        if remainder == 0
                            % 右方向
                            adjustedPoints = adjustLinePoints(existingPoints, 30, 0);
                        elseif remainder == 1
                            % 左方向
                            adjustedPoints = adjustLinePoints(existingPoints, -30, 0);
                        elseif remainder == 2
                            % 上方向
                            adjustedPoints = adjustLinePoints(existingPoints, 0, -30);
                        else
                            % 下方向
                            adjustedPoints = adjustLinePoints(existingPoints, 0, 30);
                        end

                        % 線のポイントを更新（既存の線を保持したまま位置を調整）
                        set_param(lineHandle, 'Points', adjustedPoints);
                    else
                        % 通常の線は自動配線を適用
                        try
                            set_param(lineHandle, 'autorouting', 'on');
                        catch
                            % 自動配線パラメータがない場合は無視
                        end
                    end
                catch e
                    fprintf('    Warning: Error processing line %d: %s\n', j, e.message);
                    % エラーが発生しても続行
                end
            end
        else
            % 既存の線を保持しないモード（オリジナルの動作）
            % サブシステムへの入力配線を最優先で特別に処理
            if ~isempty(subsystemInputLines)
                fprintf('  - Prioritizing subsystem input lines optimization...\n');

                % 自動配線を無効化して手動で配線を設定
                for j = 1:length(subsystemInputLines)
                    try
                        lineHandle = subsystemInputLines(j);
                        % 自動配線を無効化
                        try
                            set_param(lineHandle, 'autorouting', 'off');
                        catch
                            % 自動配線パラメータがない場合は無視
                        end
                    catch
                        % エラーが発生しても続行
                    end
                end

                % サブシステム入力配線を特別に処理
                optimizeSubsystemInputLines(subsystemInputLines);

                % 変更を確実に反映させるために少し待機
                pause(0.1);
            end

            % 分岐点の最適化を実行
            try
                fprintf('    Optimizing branch points in %s...\n', subsystemName);
                optimizeBranchPoints(subsystemName, lines);
            catch branchE
                fprintf('    Warning: Failed to optimize branch points: %s\n', branchE.message);
            end

            % Simulinkの組み込み機能を使用して配線を整理（サブシステム入力配線以外）
            nonInputLines = setdiff(lines, subsystemInputLines);
            if ~isempty(nonInputLines)
                try
                    Simulink.BlockDiagram.routeLine(nonInputLines);
                    fprintf('    Successfully routed %d non-input lines in %s\n', length(nonInputLines), subsystemName);
                catch e
                    fprintf('    Warning: Error routing non-input lines: %s\n', e.message);
                end
            end
        end

        % 配線の交差を検出して調整
        try
            optimizeCrossings(subsystemName, lines);
        catch crossE
            fprintf('    Warning: Failed to optimize crossings: %s\n', crossE.message);
        end

        % サブシステム入力配線を再度処理して、他の処理で上書きされた場合に元に戻す
        if ~isempty(subsystemInputLines)
            fprintf('  - Re-optimizing subsystem input lines to ensure proper layout...\n');
            optimizeSubsystemInputLines(subsystemInputLines);
        end

        fprintf('    Completed optimization for %s\n', subsystemName);
    catch e
        fprintf('    Error processing subsystem %s: %s\n', subsystemName, e.message);
        fprintf('    Error details: %s\n', getReport(e, 'basic'));
    end
end

function subsystemInputLines = identifySubsystemInputLines(systemName, lines)
    % サブシステムへの入力配線を特定する関数
    subsystemInputLines = [];

    % システム内のすべてのブロックを取得
    blocks = find_system(systemName, 'SearchDepth', 1, 'LookUnderMasks', 'all', 'FollowLinks', 'on');

    % サブシステムブロックを特定
    subsystemBlocks = {};
    for i = 1:length(blocks)
        try
            blockType = get_param(blocks{i}, 'BlockType');
            if strcmp(blockType, 'SubSystem') || strcmp(blockType, 'ModelReference')
                subsystemBlocks{end+1} = blocks{i};
            end
        catch
            continue;
        end
    end

    % サブシステムがない場合は終了
    if isempty(subsystemBlocks)
        return;
    end

    % 各ラインを処理
    for i = 1:length(lines)
        try
            lineHandle = lines(i);

            % デスティネーションポートを取得
            dstPorts = get_param(lineHandle, 'DstPortHandle');

            if isempty(dstPorts) || all(dstPorts == -1)
                continue;
            end

            % 各デスティネーションポートを処理
            for j = 1:length(dstPorts)
                dstPort = dstPorts(j);

                % デスティネーションブロックを取得
                dstBlock = get_param(dstPort, 'Parent');

                % サブシステムへの入力配線かどうかを確認
                for k = 1:length(subsystemBlocks)
                    if strcmp(dstBlock, subsystemBlocks{k})
                        subsystemInputLines(end+1) = lineHandle;
                        break;
                    end
                end
            end
        catch
            continue;
        end
    end

    % 重複を削除
    subsystemInputLines = unique(subsystemInputLines);
end

function optimizeSubsystemInputLines(lineHandles)
    % サブシステムへの入力配線を最適化する関数
    fprintf('    Optimizing subsystem input lines...\n');

    % 各ラインの情報を収集
    lineInfo = struct('handle', {}, 'srcPos', {}, 'dstPos', {}, 'dstBlock', {}, 'dstPort', {}, 'portNumber', {});

    for i = 1:length(lineHandles)
        try
            lineHandle = lineHandles(i);

            % ソースとデスティネーションの情報を取得
            srcPort = get_param(lineHandle, 'SrcPortHandle');
            dstPorts = get_param(lineHandle, 'DstPortHandle');

            if srcPort == -1 || isempty(dstPorts) || dstPorts(1) == -1
                continue;
            end

            % ソースとデスティネーションの位置を取得
            srcPos = get_param(srcPort, 'Position');
            dstPos = get_param(dstPorts(1), 'Position');

            % デスティネーションブロックとポート番号を取得
            dstBlock = get_param(dstPorts(1), 'Parent');
            portNumber = get_param(dstPorts(1), 'PortNumber');

            % 情報を構造体に保存
            lineInfo(end+1) = struct('handle', lineHandle, 'srcPos', srcPos, ...
                'dstPos', dstPos, 'dstBlock', dstBlock, 'dstPort', dstPorts(1), 'portNumber', portNumber);
        catch
            continue;
        end
    end

    % デスティネーションブロックごとにグループ化
    blockGroups = containers.Map('KeyType', 'char', 'ValueType', 'any');

    for i = 1:length(lineInfo)
        blockName = lineInfo(i).dstBlock;

        if ~blockGroups.isKey(blockName)
            blockGroups(blockName) = [];
        end

        blockGroups(blockName) = [blockGroups(blockName), i];
    end

    % 各ブロックグループを処理
    blockKeys = blockGroups.keys;
    for i = 1:length(blockKeys)
        blockName = blockKeys{i};
        groupIndices = blockGroups(blockName);

        % このブロックに接続する配線を処理
        optimizeBlockInputLines(lineInfo, groupIndices);
    end
end

function optimizeBlockInputLines(lineInfo, groupIndices)
    % 特定のブロックへの入力配線を最適化する関数
    if isempty(groupIndices)
        return;
    end

    % ブロック名を取得（デバッグ用）
    blockName = lineInfo(groupIndices(1)).dstBlock;
    fprintf('    Optimizing input lines for block: %s\n', blockName);

    % ポート番号でソート
    portNumbers = zeros(length(groupIndices), 1);
    for i = 1:length(groupIndices)
        idx = groupIndices(i);
        portNumbers(i) = lineInfo(idx).portNumber;
    end

    [sortedPortNumbers, sortOrder] = sort(portNumbers);
    sortedIndices = groupIndices(sortOrder);

    % ブロックの位置情報を取得
    dstBlockPos = get_param(blockName, 'Position');
    blockLeftX = dstBlockPos(1);
    blockWidth = dstBlockPos(3) - dstBlockPos(1);
    blockHeight = dstBlockPos(4) - dstBlockPos(2);

    % グローバルパラメータを取得
    global WIRING_PARAMS;

    % 配線を整理するための共通X座標（ブロックの左側に余裕を持たせる）
    if isempty(WIRING_PARAMS)
        commonXOffset = 50;  % デフォルト値（50ピクセル）
    else
        commonXOffset = WIRING_PARAMS.commonXOffset;
    end

    commonX = blockLeftX - commonXOffset;

    % ポート数に基づいて垂直方向の間隔を計算
    totalPorts = length(sortedIndices);

    % 各配線を処理
    for i = 1:length(sortedIndices)
        idx = sortedIndices(i);
        lineHandle = lineInfo(idx).handle;
        dstPos = lineInfo(idx).dstPos;
        portNumber = lineInfo(idx).portNumber;

        try
            % 現在の配線ポイントを取得
            currentPoints = get_param(lineHandle, 'Points');
            startPoint = currentPoints(1, :);
            endPoint = currentPoints(end, :);

            % グローバルパラメータを取得
            global WIRING_PARAMS;

            % パラメータが設定されていない場合はデフォルト値を使用
            if isempty(WIRING_PARAMS)
                baseOffset = 10;  % 基本オフセット値（ピクセル）
                maxOffset = 50;   % 最大オフセット値（ピクセル）
                scaleFactor = 0.5; % スケーリング係数
            else
                baseOffset = WIRING_PARAMS.baseOffset;
                maxOffset = WIRING_PARAMS.maxOffset;
                scaleFactor = WIRING_PARAMS.scaleFactor;
            end

            % ポート番号に基づいて垂直方向のオフセットを計算
            % 各ポートに適度な高さの差を割り当てる
            % ポート番号の位置に応じて異なるオフセットを適用
            if portNumber <= totalPorts / 3
                % 上部1/3のポート
                verticalOffset = -baseOffset * (totalPorts/3 - portNumber + 1);
            elseif portNumber <= 2 * totalPorts / 3
                % 中部1/3のポート
                verticalOffset = baseOffset * (portNumber - totalPorts/3);
            else
                % 下部1/3のポート
                verticalOffset = baseOffset * (portNumber - totalPorts/3);
            end

            % 最大オフセットに制限を設ける
            if abs(verticalOffset) > maxOffset
                verticalOffset = sign(verticalOffset) * maxOffset;
            end

            % サブシステムの高さに基づいて、オフセットを調整（大きなサブシステムには大きなオフセット）
            heightScaleFactor = max(0.5, min(1.0, blockHeight / 300));  % 高さに基づくスケーリング係数
            verticalOffset = verticalOffset * scaleFactor * heightScaleFactor;

            % 強制的な配線パターンを適用
            % 複数の中間点を使用して、より明確な配線パターンを作成

            % 始点からの水平距離を計算
            horizontalDistance = abs(commonX - startPoint(1));

            % 水平距離に基づいて中間点の数を決定
            if horizontalDistance > 300
                numIntermediatePoints = 3;  % 長い距離には多くの中間点
            elseif horizontalDistance > 150
                numIntermediatePoints = 2;  % 中程度の距離
            else
                numIntermediatePoints = 1;  % 短い距離
            end

            % 新しい配線ポイントを生成
            newPoints = zeros(numIntermediatePoints + 3, 2);  % 始点、中間点、終点

            % 始点
            newPoints(1, :) = startPoint;

            % 中間点を計算
            for j = 1:numIntermediatePoints
                % 水平方向の位置を均等に分割
                xPos = startPoint(1) + (commonX - startPoint(1)) * j / (numIntermediatePoints + 1);

                % 垂直方向の位置を計算（始点から徐々に目標の高さに移動）
                if j == 1
                    % 最初の中間点は始点と同じ高さ
                    yPos = startPoint(2);
                else
                    % その他の中間点は徐々に目標の高さに近づける
                    targetY = dstPos(2) + verticalOffset;
                    progress = (j - 1) / (numIntermediatePoints - 1);  % 0から1の進捗
                    yPos = startPoint(2) + (targetY - startPoint(2)) * progress;
                end

                newPoints(j + 1, :) = [xPos, yPos];
            end

            % 共通X座標での垂直位置
            newPoints(numIntermediatePoints + 2, :) = [commonX, dstPos(2) + verticalOffset];

            % 終点
            newPoints(numIntermediatePoints + 3, :) = endPoint;

            % 配線を更新（自動配線を無効化して手動で設定）
            try
                % 自動配線を無効化
                set_param(lineHandle, 'autorouting', 'off');
            catch
                % 自動配線パラメータがない場合は無視
            end

            % 配線ポイントを設定
            set_param(lineHandle, 'Points', newPoints);

            fprintf('    Optimized line to port %d with vertical offset %.1f\n', portNumber, verticalOffset);
        catch e
            fprintf('    Warning: Error optimizing line to port %d: %s\n', portNumber, e.message);
        end
    end

    % 最後に全体の配線を整理（交差を減らすため）
    try
        % 各配線ペアの交差をチェック
        for i = 1:length(sortedIndices)-1
            for j = i+1:length(sortedIndices)
                idx1 = sortedIndices(i);
                idx2 = sortedIndices(j);

                line1 = lineInfo(idx1).handle;
                line2 = lineInfo(idx2).handle;

                % 配線の交差を調整
                adjustInputLineCrossing(line1, line2);
            end
        end
    catch e
        fprintf('    Warning: Error adjusting line crossings: %s\n', e.message);
    end
end

function adjustInputLineCrossing(line1Handle, line2Handle)
    % サブシステム入力配線の交差を調整する関数
    try
        % 配線ポイントを取得
        points1 = get_param(line1Handle, 'Points');
        points2 = get_param(line2Handle, 'Points');

        % 配線の交差を検出
        if detectLineCrossing(points1, points2)
            % 交差が検出された場合、配線2を少し下にオフセット
            newPoints2 = points2;

            % 中間点のみを調整（始点と終点は固定）
            for i = 2:size(newPoints2, 1)-1
                newPoints2(i, 2) = newPoints2(i, 2) + 15;  % 15ピクセル下にオフセット
            end

            % 配線を更新
            set_param(line2Handle, 'Points', newPoints2);
        end
    catch
        % エラーが発生しても続行
    end
end

function isCrossing = detectLineCrossing(points1, points2)
    % 2つの配線の交差を検出する関数
    isCrossing = false;

    % 各線分ペアをチェック
    for i = 1:size(points1, 1)-1
        p1 = points1(i, :);
        p2 = points1(i+1, :);

        for j = 1:size(points2, 1)-1
            p3 = points2(j, :);
            p4 = points2(j+1, :);

            % 線分の交差をチェック
            if doLineSegmentsIntersect(p1, p2, p3, p4)
                isCrossing = true;
                return;
            end
        end
    end
end

function intersect = doLineSegmentsIntersect(p1, p2, p3, p4)
    % 2つの線分が交差するかどうかをチェックする関数

    % 線分1の方向ベクトル
    v1 = p2 - p1;

    % 線分2の方向ベクトル
    v2 = p4 - p3;

    % 線分が平行かどうかをチェック
    crossProduct = v1(1) * v2(2) - v1(2) * v2(1);

    if abs(crossProduct) < 1e-10
        % 線分が平行の場合、重なっているかどうかをチェック
        intersect = false;
        return;
    end

    % 交点のパラメータを計算
    s = ((p3(1) - p1(1)) * v2(2) - (p3(2) - p1(2)) * v2(1)) / crossProduct;
    t = ((p3(1) - p1(1)) * v1(2) - (p3(2) - p1(2)) * v1(1)) / crossProduct;

    % 交点が両方の線分上にあるかどうかをチェック
    intersect = (s >= 0 && s <= 1 && t >= 0 && t <= 1);
end

function optimizeCrossings(systemName, lines)
    % 配線の交差を検出して調整する関数

    if isempty(lines)
        return;
    end

    % 各ラインのポイントを取得
    linePoints = cell(length(lines), 1);
    lineHandles = zeros(length(lines), 1);
    validLineCount = 0;

    for i = 1:length(lines)
        try
            if ishandle(lines(i))
                linePoints{i} = get_param(lines(i), 'Points');
                lineHandles(i) = lines(i);
                validLineCount = validLineCount + 1;
            end
        catch
            linePoints{i} = [];
            lineHandles(i) = -1;
        end
    end

    % 潜在的な交差の数を推定
    potentialCrossings = 0;
    crossingPairs = [];

    for i = 1:length(linePoints)
        for j = i+1:length(linePoints)
            if ~isempty(linePoints{i}) && ~isempty(linePoints{j}) && lineHandles(i) > 0 && lineHandles(j) > 0
                % 2つのラインのバウンディングボックスが重なっているかチェック
                iMinX = min(linePoints{i}(:,1));
                iMaxX = max(linePoints{i}(:,1));
                iMinY = min(linePoints{i}(:,2));
                iMaxY = max(linePoints{i}(:,2));

                jMinX = min(linePoints{j}(:,1));
                jMaxX = max(linePoints{j}(:,1));
                jMinY = min(linePoints{j}(:,2));
                jMaxY = max(linePoints{j}(:,2));

                % バウンディングボックスが重なっている場合、潜在的な交差としてカウント
                if iMinX <= jMaxX && iMaxX >= jMinX && iMinY <= jMaxY && iMaxY >= jMinY
                    potentialCrossings = potentialCrossings + 1;
                    crossingPairs(potentialCrossings, :) = [i j];
                end
            end
        end
    end

    if potentialCrossings > 0
        fprintf('    Found %d potential line crossings in %s\n', potentialCrossings, systemName);

        % 交差している配線ペアを優先的に調整
        for k = 1:min(size(crossingPairs, 1), 10)  % 最大10ペアまで処理
            i = crossingPairs(k, 1);
            j = crossingPairs(k, 2);

            if lineHandles(i) > 0 && lineHandles(j) > 0
                try
                    % 交差している配線ペアを調整
                    adjustCrossingLines(lineHandles(i), lineHandles(j), linePoints{i}, linePoints{j});
                catch e
                    fprintf('    Warning: Error adjusting crossing lines: %s\n', e.message);
                end
            end
        end
    end
end







function points = removeRedundantPoints(points)
    % 配線のポイントを最適化する関数
    % 人間の配線最適化原則に基づいて配線を整理：
    % 1. できるだけ直線的な配線を維持する（垂直・水平の線を優先）
    % 2. 配線の交差を最小限に抑える
    % 3. 全体的に美しく整理されたレイアウトを実現する

    % 入力チェック
    if size(points, 1) < 3
        % ポイントが3つ未満の場合は処理不要
        return;
    end

    % 始点と終点を保存（元の接続を維持するため）
    startPoint = points(1, :);
    endPoint = points(end, :);

    % 始点と終点の直線距離を計算
    dx = abs(endPoint(1) - startPoint(1));
    dy = abs(endPoint(2) - startPoint(2));

    % 始点と終点がほぼ一直線上にある場合は完全な直線にする
    if dx < 5 || dy < 5
        % X座標またはY座標の差が小さい場合は完全な直線
        points = [startPoint; endPoint];
        return;
    end

    % 最初に重複ポイントを削除
    i = 1;
    while i < size(points, 1)
        p1 = points(i, :);
        p2 = points(i+1, :);

        % 同じ位置のポイントが連続している場合は削除
        if all(p1 == p2)
            points(i+1, :) = [];
        else
            i = i + 1;
        end
    end

    % 3点が一直線上にある場合、中間点を削除してより直線的な配線を実現
    i = 1;
    while i < size(points, 1) - 1
        p1 = points(i, :);
        p2 = points(i+1, :);
        p3 = points(i+2, :);

        % 水平または垂直の直線上にある場合
        if (p1(1) == p2(1) && p2(1) == p3(1)) || (p1(2) == p2(2) && p2(2) == p3(2))
            % 中間点を削除
            points(i+1, :) = [];
        else
            % 斜めの直線上にある場合も考慮
            % 3点が一直線上にあるかどうかを判定（より厳密な判定）
            if abs((p3(2) - p1(2)) * (p2(1) - p1(1)) - (p2(2) - p1(2)) * (p3(1) - p1(1))) < 1e-10
                % 中間点を削除
                points(i+1, :) = [];
            else
                i = i + 1;
            end
        end
    end

    % ポイント数が多すぎる場合は、最小限のポイントで直線的な配線を生成
    if size(points, 1) > 4
        % 配線の方向を分析
        if dx >= dy
            % 水平方向主体の場合は最小限の折れ点で直線的に
            midX = (startPoint(1) + endPoint(1)) / 2;
            points = [
                startPoint;
                midX, startPoint(2);
                midX, endPoint(2);
                endPoint
            ];
        else
            % 垂直方向主体の場合は最小限の折れ点で直線的に
            midY = (startPoint(2) + endPoint(2)) / 2;
            points = [
                startPoint;
                startPoint(1), midY;
                endPoint(1), midY;
                endPoint
            ];
        end
    else
        % 人間の配線パターンを模倣：垂直・水平の配線を優先
        % 斜め線を垂直・水平の組み合わせに変換（より美しいレイアウトのため）
        if size(points, 1) >= 2
            i = 1;
            while i < size(points, 1)
                p1 = points(i, :);
                p2 = points(i+1, :);

                % 斜め線の場合
                dx_local = abs(p2(1) - p1(1));
                dy_local = abs(p2(2) - p1(2));

                if dx_local > 0 && dy_local > 0
                    % 斜め線を垂直・水平の組み合わせに変換
                    % 配線の方向に基づいて最適な変換方法を選択
                    if dx_local < dy_local
                        % 水平→垂直の順に変換（Y方向の変化が大きい場合）
                        newPoint = [p2(1), p1(2)];
                        points = [points(1:i, :); newPoint; points(i+1:end, :)];
                    else
                        % 垂直→水平の順に変換（X方向の変化が大きい場合）
                        newPoint = [p1(1), p2(2)];
                        points = [points(1:i, :); newPoint; points(i+1:end, :)];
                    end
                    i = i + 2;  % 新しいポイントを追加したので2つ進める
                else
                    i = i + 1;
                end
            end
        end
    end

    % 最後に再度冗長なポイントを削除して配線をシンプルに
    i = 1;
    while i < size(points, 1) - 1
        p1 = points(i, :);
        p2 = points(i+1, :);
        p3 = points(i+2, :);

        % 水平または垂直の直線上にある場合
        if (p1(1) == p2(1) && p2(1) == p3(1)) || (p1(2) == p2(2) && p2(2) == p3(2))
            % 中間点を削除
            points(i+1, :) = [];
        else
            i = i + 1;
        end
    end

    % 最終的なチェック：ポイント数が最小限になっているか確認
    if size(points, 1) > 4
        % まだポイント数が多い場合は、強制的に最小限のポイントに削減
        if dx >= dy
            % 水平方向主体の場合
            points = [
                startPoint;
                endPoint(1), startPoint(2);
                endPoint
            ];
        else
            % 垂直方向主体の場合
            points = [
                startPoint;
                startPoint(1), endPoint(2);
                endPoint
            ];
        end
    end

    % 始点と終点を元に戻す（安全対策）
    points(1, :) = startPoint;
    points(end, :) = endPoint;
end

function saveModelImage(systemName, outputPath)
    % Simulinkモデルまたはサブシステムの画像を保存する関数
    try
        % システムを開く（サブシステムの場合）
        if ~strcmp(bdroot, systemName)
            try
                open_system(systemName);
            catch e
                fprintf('  Warning: Could not open system %s: %s\n', systemName, e.message);
                return;
            end
        end

        % 出力ディレクトリが存在するか確認
        [outputDir, ~, ~] = fileparts(outputPath);
        if ~isempty(outputDir) && ~exist(outputDir, 'dir')
            mkdir(outputDir);
        end

        % 画像を保存（print関数の代わりにsaveas関数を使用）
        try
            % 現在のシステムのハンドルを取得
            h = get_param(systemName, 'Handle');

            % 画像を保存
            saveas(h, outputPath, 'png');
            fprintf('  Image saved to: %s\n', outputPath);
        catch e1
            fprintf('  Warning: Error using saveas: %s\n', e1.message);

            % 代替方法としてprint関数を試す
            try
                print(systemName, '-dpng', outputPath);
                fprintf('  Image saved using print to: %s\n', outputPath);
            catch e2
                fprintf('  Warning: Error using print: %s\n', e2.message);
                error('Failed to save image');
            end
        end
    catch e
        fprintf('  Warning: Error saving image: %s\n', e.message);
    end
end







function score = evaluateImageWithAI(imagePath, beforeImagePath)
    % 画像を評価して配線の品質スコアを計算する関数（比較評価版）
    % Augmentのエージェントモードを使用して実際に画像をアップロードし評価する
    % APIキーが設定されていない場合は手動評価モードに切り替わります
    %
    % 入力:
    %   imagePath - 評価する画像のパス（最適化後）
    %   beforeImagePath - 比較用の画像のパス（最適化前、省略可能）
    % 出力:
    %   score - 配線品質の評価スコア（高いほど良い）
    %
    % 注意:
    %   自動評価を使用するには環境変数 AUGMENT_API_KEY を設定してください
    %   APIキーが設定されていない場合は手動評価モードに切り替わります

    % 画像の存在を確認
    if ~exist(imagePath, 'file')
        fprintf('  Warning: Image file not found: %s\n', imagePath);
        score = 0;
        return;
    end

    % 比較用画像が指定されている場合はその存在も確認
    isComparisonMode = nargin > 1 && ~isempty(beforeImagePath);
    if isComparisonMode && ~exist(beforeImagePath, 'file')
        fprintf('  Warning: Before image file not found: %s\n', beforeImagePath);
        isComparisonMode = false;
    end

    try
        % Augmentエージェントを使用して画像をアップロードし評価
        fprintf('  Attempting to use Augment AI for evaluation...\n');

        % 直接Pythonスクリプトを実行
        % スクリプトのパスを取得（カレントディレクトリ内の evaluate_simulink_image.py）
        scriptPath = fullfile(pwd, 'evaluate_simulink_image.py');

        % スクリプトが存在するか確認
        if ~exist(scriptPath, 'file')
            error('Python script not found: %s', scriptPath);
        end

        % Pythonスクリプトを実行
        if isComparisonMode
            cmd = sprintf('python "%s" "%s" "%s"', scriptPath, imagePath, beforeImagePath);
        else
            cmd = sprintf('python "%s" "%s"', scriptPath, imagePath);
        end

        fprintf('  Executing: %s\n', cmd);
        [status, cmdout] = system(cmd);

        % APIキーが設定されていないかどうかを確認
        if status ~= 0 || contains(cmdout, 'NO_API_KEY:')
            if contains(cmdout, 'NO_API_KEY:')
                fprintf('  Info: %s\n', regexprep(cmdout, '.*NO_API_KEY:', 'NO_API_KEY:'));
                fprintf('  Switching to manual evaluation mode...\n');
            else
                fprintf('  Warning: Python script execution failed with status %d\n', status);
                fprintf('  Output: %s\n', cmdout);
                fprintf('  Falling back to manual evaluation...\n');
            end

            % 手動評価モードに切り替え
            fprintf('\n手動評価モードです。画像を確認して評価してください。\n');
            if isComparisonMode
                fprintf('  最適化前の画像: %s\n', beforeImagePath);
            end
            fprintf('  評価する画像: %s\n', imagePath);
            fprintf('  0〜100の範囲でスコアを入力してください: ');

            userInput = input('');

            % 入力値の検証
            if isempty(userInput) || ~isnumeric(userInput) || userInput < 0 || userInput > 100
                fprintf('  Warning: 無効な入力です。デフォルト値の50を使用します。\n');
                score = 50;
            else
                score = userInput;
            end
        else
            % 出力からスコアを抽出
            fprintf('  Python script output:\n%s\n', cmdout);

            % 最後の行からスコアを抽出
            scorePattern = 'SCORE:(\d+)';
            scoreMatch = regexp(cmdout, scorePattern, 'tokens');

            if ~isempty(scoreMatch) && ~isempty(scoreMatch{end})
                score = str2double(scoreMatch{end}{1});
                fprintf('  Extracted score: %.1f\n', score);
            else
                fprintf('  Warning: Could not extract score from output, using default value\n');
                score = 50;  % デフォルト値
            end
        end

        % 外部Pythonスクリプトを使用するため、一時ファイルの削除は不要

    catch e
        fprintf('  Error during AI evaluation: %s\n', e.message);
        fprintf('  Stack trace: %s\n', getReport(e, 'basic'));

        % エラーが発生した場合はユーザーに手動で評価を求める
        fprintf('  Falling back to manual evaluation due to error...\n');

        fprintf('\n手動評価モードです。画像を確認して評価してください。\n');
        if isComparisonMode
            fprintf('  最適化前の画像: %s\n', beforeImagePath);
        end
        fprintf('  評価する画像: %s\n', imagePath);
        fprintf('  0〜100の範囲でスコアを入力してください: ');

        userInput = input('');

        % 入力値の検証
        if isempty(userInput) || ~isnumeric(userInput) || userInput < 0 || userInput > 100
            fprintf('  Warning: 無効な入力です。デフォルト値の50を使用します。\n');
            score = 50;
        else
            score = userInput;
        end
    end

    fprintf('  最終評価スコア: %.1f\n', score);
    return;
end



function [bestParams, bestScore] = optimizeWiringParameters(modelName, subsystemName)
    % AIを使用して配線パラメータを最適化する関数
    % 入力:
    %   modelName - モデル名
    %   subsystemName - サブシステム名（オプション）
    % 出力:
    %   bestParams - 最適化されたパラメータ
    %   bestScore - 最適化後のスコア

    fprintf('Starting AI-based wiring parameter optimization for %s...\n', subsystemName);

    % モデル名から拡張子を除去（拡張子がある場合）
    [~, modelBaseName, ext] = fileparts(modelName);
    if isempty(ext)
        % 拡張子が指定されていない場合はデフォルトの拡張子を追加
        modelFullName = [modelName, '.slx'];
    else
        % 拡張子が指定されている場合はそのまま使用
        modelFullName = modelName;
    end

    % 対象システム名を設定
    if nargin < 2 || isempty(subsystemName)
        targetSystem = modelBaseName;
    else
        targetSystem = subsystemName;
    end

    % 画像出力用のフォルダを作成
    outputDir = 'optimization_images';
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    % 最適化前の画像を保存
    beforeImagePath = fullfile(outputDir, [strrep(targetSystem, '/', '_'), '_before.png']);
    try
        saveModelImage(targetSystem, beforeImagePath);
    catch e
        fprintf('Warning: Could not save before image: %s\n', e.message);
        beforeImagePath = '';
    end

    % パラメータの範囲を定義
    paramRanges = struct();
    paramRanges.baseOffset = [5, 10, 15, 20, 25];  % 基本オフセット値
    paramRanges.maxOffset = [30, 40, 50, 60, 70];  % 最大オフセット値
    paramRanges.commonXOffset = [30, 40, 50, 60, 70, 80];  % 共通X座標のオフセット
    paramRanges.scaleFactor = [0.3, 0.5, 0.7, 1.0, 1.2];  % スケーリング係数

    % 最適化の反復回数
    maxIterations = 3;  % AIによる評価は時間がかかるため、反復回数を減らす

    % 最良のパラメータとスコアを初期化
    bestParams = struct('baseOffset', 10, 'maxOffset', 50, 'commonXOffset', 50, 'scaleFactor', 0.5);
    bestScore = 0;

    % 最良モデルのファイル名を定義
    bestModelName = [modelBaseName, '_best'];
    bestModelFile = [bestModelName, '.slx'];

    % 最良モデルが存在する場合は削除（新しい最適化を開始するため）
    if exist(bestModelFile, 'file')
        fprintf('Removing existing best model file: %s\n', bestModelFile);
        if bdIsLoaded(bestModelName)
            close_system(bestModelName, 0);
        end
        delete(bestModelFile);
    end

    % 最適化ループ
    for iteration = 1:maxIterations
        fprintf('Optimization iteration %d/%d...\n', iteration, maxIterations);

        % 現在のイテレーションのパラメータセットを生成
        if iteration == 1
            % 初回は複数のパラメータセットを試行
            paramSets = generateParameterSets(paramRanges, 3);  % AIによる評価は時間がかかるため、セット数を減らす
        else
            % 2回目以降は最良のパラメータを中心に探索
            paramSets = refineParameterSets(bestParams, paramRanges, 2);
        end

        % 各パラメータセットを評価
        scores = zeros(length(paramSets), 1);
        for i = 1:length(paramSets)
            params = paramSets{i};
            fprintf('  Testing parameter set %d/%d: baseOffset=%.1f, maxOffset=%.1f, commonXOffset=%.1f, scaleFactor=%.2f\n', ...
                i, length(paramSets), params.baseOffset, params.maxOffset, params.commonXOffset, params.scaleFactor);

            % パラメータを適用して配線を最適化
            imagePath = applyAndEvaluateParameters(modelBaseName, targetSystem, params, outputDir, i, iteration);

            % 結果をAIで評価
            if ~isempty(imagePath) && exist(imagePath, 'file')
                if i == 1 && iteration == 1 && ~isempty(beforeImagePath) && exist(beforeImagePath, 'file')
                    % 最初のイテレーションの最初のパラメータセットの場合、beforeImagePathと比較
                    scores(i) = evaluateImageWithAI(imagePath, beforeImagePath);
                else
                    % それ以外の場合は単独で評価
                    scores(i) = evaluateImageWithAI(imagePath);
                end
            else
                scores(i) = 0;
            end
        end

        % 最良のパラメータセットを見つける
        [maxScore, maxIdx] = max(scores);
        if maxScore > bestScore
            bestScore = maxScore;
            bestParams = paramSets{maxIdx};
            fprintf('  Found better parameters: baseOffset=%.1f, maxOffset=%.1f, commonXOffset=%.1f, scaleFactor=%.2f (score: %.2f)\n', ...
                bestParams.baseOffset, bestParams.maxOffset, bestParams.commonXOffset, bestParams.scaleFactor, bestScore);

            % 最良モデルを更新
            tempFile = [modelBaseName, '_temp.slx'];
            if exist(tempFile, 'file')
                fprintf('  Updating best model with current result...\n');

                % 既存のモデルを閉じる
                if bdIsLoaded(tempModelName)
                    close_system(tempModelName, 0);
                end
                if bdIsLoaded(bestModelName)
                    close_system(bestModelName, 0);
                end

                % 一時モデルを最良モデルとしてコピー
                copyfile(tempFile, bestModelFile, 'f');
                fprintf('  Best model updated: %s\n', bestModelFile);
            else
                fprintf('  Warning: Temporary model file not found, cannot update best model\n');
            end
        else
            fprintf('  No improvement in this iteration. Best score remains: %.2f\n', bestScore);
        end
    end

    % 最終的な最適化結果を適用
    fprintf('Applying final optimized parameters...\n');

    % 最良モデルが存在するか確認
    if exist(bestModelFile, 'file')
        fprintf('  Using best model for final optimization: %s\n', bestModelFile);

        % 既存のモデルを閉じる
        if bdIsLoaded(modelBaseName)
            close_system(modelBaseName, 0);
        end
        if bdIsLoaded(bestModelName)
            close_system(bestModelName, 0);
        end

        % 最良モデルを元のモデルとしてコピー
        copyfile(bestModelFile, [modelBaseName, '.slx'], 'f');

        % 元のモデルを開く
        load_system(modelBaseName);
        fprintf('  Original model updated with best result\n');

        % 最終的な画像を生成
        finalImagePath = applyAndEvaluateParameters(modelBaseName, targetSystem, bestParams, outputDir, 0, 'final');
    else
        fprintf('  Warning: Best model file not found: %s\n', bestModelFile);

        % 元のモデルが読み込まれているか確認
        if ~bdIsLoaded(modelBaseName)
            fprintf('  Loading original model: %s\n', modelBaseName);
            try
                load_system(modelBaseName);
            catch e
                fprintf('  Warning: Error loading original model: %s\n', e.message);

                % バックアップファイルが存在する場合は、それを使用して復元
                backupFile = [modelBaseName, '_backup.slx'];
                if exist(backupFile, 'file')
                    fprintf('  Restoring from backup file: %s\n', backupFile);
                    copyfile(backupFile, [modelBaseName, '.slx'], 'f');
                    load_system(modelBaseName);
                else
                    fprintf('  Error: Cannot load original model or backup\n');
                    return;
                end
            end
        end

        % 最終的なパラメータを適用
        finalImagePath = applyAndEvaluateParameters(modelBaseName, targetSystem, bestParams, outputDir, 0, 'final');
    end

    % 最適化前後の画像を比較するための指示を表示し、最終評価を取得
    finalScore = evaluateImageWithAI(finalImagePath, beforeImagePath);

    fprintf('Optimization complete. Best parameters: baseOffset=%.1f, maxOffset=%.1f, commonXOffset=%.1f, scaleFactor=%.2f (Final score: %.1f)\n', ...
        bestParams.baseOffset, bestParams.maxOffset, bestParams.commonXOffset, bestParams.scaleFactor, finalScore);
end

function paramSets = generateParameterSets(paramRanges, count)
    % パラメータの組み合わせを生成する関数
    % 入力:
    %   paramRanges - パラメータの範囲
    %   count - 生成するパラメータセットの数
    % 出力:
    %   paramSets - パラメータセットのセル配列

    paramSets = cell(count, 1);

    % ランダムにパラメータを選択
    for i = 1:count
        params = struct();

        % 各パラメータをランダムに選択
        params.baseOffset = paramRanges.baseOffset(randi(length(paramRanges.baseOffset)));
        params.maxOffset = paramRanges.maxOffset(randi(length(paramRanges.maxOffset)));
        params.commonXOffset = paramRanges.commonXOffset(randi(length(paramRanges.commonXOffset)));
        params.scaleFactor = paramRanges.scaleFactor(randi(length(paramRanges.scaleFactor)));

        paramSets{i} = params;
    end
end

function paramSets = refineParameterSets(bestParams, paramRanges, count)
    % 最良のパラメータを中心に新しいパラメータセットを生成する関数
    % 入力:
    %   bestParams - 現在の最良パラメータ
    %   paramRanges - パラメータの範囲
    %   count - 生成するパラメータセットの数
    % 出力:
    %   paramSets - パラメータセットのセル配列

    paramSets = cell(count, 1);

    % 最良のパラメータを含める
    paramSets{1} = bestParams;

    % 最良のパラメータを中心に変動させた新しいパラメータを生成
    for i = 2:count
        params = struct();

        % 各パラメータをランダムに変動
        % baseOffset
        idx = find(paramRanges.baseOffset == bestParams.baseOffset);
        if ~isempty(idx)
            newIdx = max(1, min(length(paramRanges.baseOffset), idx + randi([-1, 1])));
            params.baseOffset = paramRanges.baseOffset(newIdx);
        else
            params.baseOffset = bestParams.baseOffset * (0.9 + 0.2 * rand());  % ±10%変動
        end

        % maxOffset
        idx = find(paramRanges.maxOffset == bestParams.maxOffset);
        if ~isempty(idx)
            newIdx = max(1, min(length(paramRanges.maxOffset), idx + randi([-1, 1])));
            params.maxOffset = paramRanges.maxOffset(newIdx);
        else
            params.maxOffset = bestParams.maxOffset * (0.9 + 0.2 * rand());  % ±10%変動
        end

        % commonXOffset
        idx = find(paramRanges.commonXOffset == bestParams.commonXOffset);
        if ~isempty(idx)
            newIdx = max(1, min(length(paramRanges.commonXOffset), idx + randi([-1, 1])));
            params.commonXOffset = paramRanges.commonXOffset(newIdx);
        else
            params.commonXOffset = bestParams.commonXOffset * (0.9 + 0.2 * rand());  % ±10%変動
        end

        % scaleFactor
        idx = find(paramRanges.scaleFactor == bestParams.scaleFactor);
        if ~isempty(idx)
            newIdx = max(1, min(length(paramRanges.scaleFactor), idx + randi([-1, 1])));
            params.scaleFactor = paramRanges.scaleFactor(newIdx);
        else
            params.scaleFactor = bestParams.scaleFactor * (0.9 + 0.2 * rand());  % ±10%変動
        end

        paramSets{i} = params;
    end
end

function imagePath = applyAndEvaluateParameters(modelName, targetSystem, params, outputDir, setIndex, iteration)
    % パラメータを適用して配線を最適化し、結果を評価する関数
    % 入力:
    %   modelName - モデル名（拡張子を含む場合あり）
    %   targetSystem - 対象システム名
    %   params - 適用するパラメータ
    %   outputDir - 画像出力ディレクトリ
    %   setIndex - パラメータセットのインデックス
    %   iteration - 最適化の反復回数
    % 出力:
    %   imagePath - 生成された画像のパス

    try
        % モデル名から拡張子を除去（拡張子がある場合）
        [~, modelBaseName, ~] = fileparts(modelName);

        % モデルが読み込まれているか確認
        if ~bdIsLoaded(modelBaseName)
            error('Model %s is not loaded', modelBaseName);
        end

        % 対象システムの存在を確認
        try
            % get_paramを使用してサブシステムの存在を確認
            get_param(targetSystem, 'Type');
        catch
            error('Target system %s does not exist', targetSystem);
        end

        % バックアップと一時モデルの名前とファイルパスを定義
        backupModelName = [modelBaseName, '_backup'];
        backupFile = [backupModelName, '.slx'];
        tempModelName = [modelBaseName, '_temp'];
        tempFile = [tempModelName, '.slx'];

        fprintf('  Preparing for optimization...\n');

        % 既存の一時モデルをクローズ（存在する場合）
        if bdIsLoaded(tempModelName)
            fprintf('  Closing existing temporary model...\n');
            close_system(tempModelName, 0);
        end

        % 既存のバックアップモデルをクローズ（存在する場合）
        if bdIsLoaded(backupModelName)
            fprintf('  Closing existing backup model...\n');
            close_system(backupModelName, 0);
        end

        % 既存の一時ファイルを削除
        if exist(tempFile, 'file')
            fprintf('  Removing existing temporary file: %s\n', tempFile);
            delete(tempFile);
        end

        % 既存のバックアップファイルを削除
        if exist(backupFile, 'file')
            fprintf('  Removing existing backup file: %s\n', backupFile);
            delete(backupFile);
        end

        % 元のモデルのバックアップを作成（復元用）
        try
            fprintf('  Saving backup model: %s\n', backupModelName);

            % 現在のモデルのハンドルを取得
            h = get_param(modelBaseName, 'Handle');

            % バックアップモデルを作成
            save_system(h, backupFile);
            fprintf('  Created backup model: %s\n', backupModelName);

            % バックアップファイルの存在を確認
            if ~exist(backupFile, 'file')
                fprintf('  Warning: Failed to create backup file: %s\n', backupFile);
                error('Backup file creation failed');
            end
        catch e
            fprintf('  Warning: Error creating backup model: %s\n', e.message);
            error('Failed to create backup model');
        end

        % 一時モデルを作成（最適化用）
        try
            fprintf('  Saving temporary model: %s\n', tempModelName);

            % バックアップからコピーして一時モデルを作成
            copyfile(backupFile, tempFile, 'f');
            fprintf('  Created temporary model: %s\n', tempModelName);

            % 一時ファイルの存在を確認
            if ~exist(tempFile, 'file')
                fprintf('  Warning: Failed to create temporary file: %s\n', tempFile);
                error('Temporary file creation failed');
            end
        catch e
            fprintf('  Warning: Error creating temporary model: %s\n', e.message);
            error('Failed to create temporary model');
        end

        % パラメータを適用
        applyWiringParameters(tempModelName, params);

        % 一時モデルを開く
        try
            % 一時ファイルの存在を確認
            tempFile = [tempModelName, '.slx'];
            if ~exist(tempFile, 'file')
                fprintf('  Warning: Temporary file not found: %s\n', tempFile);
                error('Temporary model file not found');
            end

            if ~bdIsLoaded(tempModelName)
                fprintf('  Loading temporary model: %s\n', tempModelName);
                load_system(tempFile);
            end

            % 対象システムのフルパスを構築
            if ~contains(targetSystem, '/')
                % ターゲットシステムがフルパスでない場合、一時モデル名を追加
                fullTargetSystem = [tempModelName, '/', targetSystem];
            else
                % ターゲットシステムがフルパスの場合、モデル名部分を一時モデル名に置き換え
                parts = strsplit(targetSystem, '/');
                parts{1} = tempModelName;
                fullTargetSystem = strjoin(parts, '/');
            end

            % 対象システムの配線を最適化
            fprintf('  Optimizing wiring for system: %s\n', fullTargetSystem);
            try
                optimizeSubsystemWiring(fullTargetSystem, true);
            catch e
                fprintf('  Warning: Error optimizing subsystem wiring: %s\n', e.message);
                fprintf('  Trying with original target system name: %s\n', targetSystem);

                % 元のターゲットシステム名でも試す
                try
                    optimizeSubsystemWiring(targetSystem, true);
                catch e2
                    fprintf('  Warning: Error optimizing with original name: %s\n', e2.message);
                    error('Failed to optimize subsystem wiring');
                end
            end
        catch e
            fprintf('  Warning: Error during optimization: %s\n', e.message);
            error('Failed during optimization process');
        end

        % 画像を保存
        if ischar(iteration)
            imageName = sprintf('%s_%s_set%d.png', strrep(targetSystem, '/', '_'), iteration, setIndex);
        else
            imageName = sprintf('%s_iter%d_set%d.png', strrep(targetSystem, '/', '_'), iteration, setIndex);
        end
        imagePath = fullfile(outputDir, imageName);

        try
            fprintf('  Saving model image to: %s\n', imagePath);

            % 対象システムのフルパスを使用
            if exist('fullTargetSystem', 'var') && ~isempty(fullTargetSystem)
                fprintf('  Using full target system path: %s\n', fullTargetSystem);
                saveModelImage(fullTargetSystem, imagePath);
            else
                fprintf('  Using original target system path: %s\n', targetSystem);
                saveModelImage(targetSystem, imagePath);
            end

            % 画像が正常に保存されたか確認
            if ~exist(imagePath, 'file')
                fprintf('  Warning: Image file was not created\n');
            else
                fprintf('  Image successfully saved to: %s\n', imagePath);
            end
        catch e
            fprintf('  Warning: Error saving model image: %s\n', e.message);
            imagePath = '';
        end

        % 一時モデルを閉じる
        try
            if bdIsLoaded(tempModelName)
                fprintf('  Closing temporary model...\n');
                close_system(tempModelName, 0);  % 保存せずに閉じる
            end
        catch e
            fprintf('  Warning: Error closing temporary model: %s\n', e.message);
        end

        % 一時ファイルを削除
        tempFile = [tempModelName, '.slx'];
        if exist(tempFile, 'file')
            try
                fprintf('  Removing temporary file...\n');
                delete(tempFile);
            catch e
                fprintf('  Warning: Error removing temporary file: %s\n', e.message);
            end
        end

        % ユーザーに確認（最終イテレーションの場合のみ）
        if ischar(iteration) && strcmp(iteration, 'final')
            fprintf('\n最適化結果を確認してください。\n');
            fprintf('  最適化前の画像: %s\n', fullfile(outputDir, [strrep(targetSystem, '/', '_'), '_before.png']));
            fprintf('  最適化後の画像: %s\n', imagePath);
            fprintf('  この結果に満足しますか？ (y/n): ');

            % ユーザー入力を待機
            userInput = input('', 's');

            if ~strcmpi(userInput, 'y')
                % ユーザーが満足していない場合、元のモデルに戻す
                fprintf('  元のモデルに戻します...\n');

                % 現在開いているモデルを閉じる
                if bdIsLoaded(tempModelName)
                    fprintf('  一時モデルを閉じています...\n');
                    close_system(tempModelName, 0);  % 保存せずに閉じる
                end

                if bdIsLoaded(modelBaseName)
                    fprintf('  元のモデルを閉じています...\n');
                    close_system(modelBaseName, 0);  % 保存せずに閉じる
                end

                % バックアップファイルのパスを再構築
                backupFile = [modelBaseName, '_backup.slx'];

                % バックアップファイルが存在する場合は、それを使用して復元
                if exist(backupFile, 'file')
                    fprintf('  バックアップファイルから復元しています: %s\n', backupFile);

                    % バックアップを元のモデル名にコピー
                    fprintf('  バックアップを元のモデルにコピーしています...\n');
                    copyfile(backupFile, [modelBaseName, '.slx'], 'f');

                    % 元のモデルを開く
                    fprintf('  復元したモデルを開いています...\n');
                    load_system(modelBaseName);
                    fprintf('  モデルを復元しました: %s\n', modelBaseName);

                    % バックアップファイルを削除
                    fprintf('  バックアップファイルを削除しています...\n');
                    delete(backupFile);
                else
                    fprintf('  Warning: バックアップファイルが見つかりません: %s\n', backupFile);

                    % 元のモデルファイルが存在する場合は開く
                    if exist([modelBaseName, '.slx'], 'file')
                        fprintf('  元のモデルを開いています...\n');
                        load_system(modelBaseName);
                    else
                        fprintf('  Error: 元のモデルファイルも見つかりません: %s.slx\n', modelBaseName);
                    end
                end
            else
                fprintf('  最適化結果を採用します。\n');
            end
        end

        % バックアップファイルは削除せず、次のイテレーションのために保持
        backupFile = [modelBaseName, '_backup.slx'];
        if exist(backupFile, 'file')
            fprintf('  Keeping backup file for next iteration: %s\n', backupFile);
        else
            fprintf('  Warning: Backup file not found: %s\n', backupFile);

            % バックアップファイルがない場合は、元のモデルからバックアップを作成
            try
                fprintf('  Creating new backup from original model...\n');
                if bdIsLoaded(modelBaseName)
                    % 現在のモデルのハンドルを取得
                    h = get_param(modelBaseName, 'Handle');

                    % バックアップモデルを作成
                    save_system(h, backupFile);
                    fprintf('  Created new backup model: %s\n', backupModelName);
                end
            catch e
                fprintf('  Warning: Error creating new backup: %s\n', e.message);
            end
        end

    catch e
        fprintf('  Warning: Error applying parameters: %s\n', e.message);
        imagePath = '';

        % エラーが発生した場合、元のモデルに戻す
        try
            fprintf('  エラーが発生したため、元のモデルに戻します...\n');

            % モデル名から拡張子を除去（拡張子がある場合）
            [~, modelBaseName, ~] = fileparts(modelName);

            % 開いているモデルをすべて閉じる
            % 元のモデルが開いている場合は閉じる
            if bdIsLoaded(modelBaseName)
                fprintf('  元のモデルを閉じています...\n');
                close_system(modelBaseName, 0);  % 保存せずに閉じる
            end

            % 一時モデルが開いている場合は閉じる
            tempModelName = [modelBaseName, '_temp'];
            if bdIsLoaded(tempModelName)
                fprintf('  一時モデルを閉じています...\n');
                close_system(tempModelName, 0);
            end

            % バックアップモデルが開いている場合は閉じる
            backupModelName = [modelBaseName, '_backup'];
            if bdIsLoaded(backupModelName)
                fprintf('  バックアップモデルを閉じています...\n');
                close_system(backupModelName, 0);
            end

            % バックアップファイルのパスを再構築
            backupFile = [modelBaseName, '_backup.slx'];

            % バックアップファイルが存在する場合は、それを使用して復元
            if exist(backupFile, 'file')
                fprintf('  バックアップファイルから復元しています: %s\n', backupFile);

                % バックアップを元のモデル名にコピー
                fprintf('  バックアップを元のモデルにコピーしています...\n');
                copyfile(backupFile, [modelBaseName, '.slx'], 'f');

                % 元のモデルを開く
                fprintf('  復元したモデルを開いています...\n');
                load_system(modelBaseName);
                fprintf('  モデルを復元しました: %s\n', modelBaseName);

                % バックアップファイルは削除せず、次のイテレーションのために保持
                fprintf('  バックアップファイルを保持しています: %s\n', backupFile);
            else
                fprintf('  Warning: バックアップファイルが見つかりません: %s\n', backupFile);

                % 元のモデルファイルが存在する場合は開く
                if exist([modelBaseName, '.slx'], 'file')
                    fprintf('  元のモデルを開いています...\n');
                    load_system(modelBaseName);
                else
                    fprintf('  Error: 元のモデルファイルも見つかりません: %s.slx\n', modelBaseName);
                end
            end

            % 一時ファイルを削除
            tempFile = [tempModelName, '.slx'];
            if exist(tempFile, 'file')
                fprintf('  一時ファイルを削除しています: %s\n', tempFile);
                delete(tempFile);
            end
        catch restoreError
            fprintf('  Warning: Error restoring model: %s\n', restoreError.message);
        end
    end
end

function applyWiringParameters(~, params)
    % 配線最適化パラメータをグローバル変数に設定する関数
    % 入力:
    %   ~ - 未使用の引数（モデル名）
    %   params - 適用するパラメータ

    % グローバル変数を宣言
    global WIRING_PARAMS;

    % パラメータを設定
    WIRING_PARAMS = params;

    fprintf('  Applied wiring parameters: baseOffset=%.1f, maxOffset=%.1f, commonXOffset=%.1f, scaleFactor=%.2f\n', ...
        params.baseOffset, params.maxOffset, params.commonXOffset, params.scaleFactor);
end

function subsystems = findAllSubsystems(modelName)
    % モデル内のすべてのサブシステムを見つける関数
    % 入力:
    %   modelName - モデル名
    % 出力:
    %   subsystems - サブシステムのセル配列

    try
        % モデル内のすべてのブロックを取得
        allBlocks = find_system(modelName, 'FollowLinks', 'on', 'LookUnderMasks', 'all');

        % サブシステムのみをフィルタリング
        % 事前に配列を割り当て（最大でallBlocksと同じサイズ）
        subsystems = cell(length(allBlocks), 1);
        subsystemCount = 0;

        for i = 1:length(allBlocks)
            try
                blockType = get_param(allBlocks{i}, 'BlockType');
                if strcmp(blockType, 'SubSystem') || strcmp(blockType, 'ModelReference')
                    subsystemCount = subsystemCount + 1;
                    subsystems{subsystemCount} = allBlocks{i};
                end
            catch
                continue;
            end
        end

        % 実際に使用したサイズに切り詰める
        subsystems = subsystems(1:subsystemCount);

        fprintf('Found %d subsystems in model %s\n', subsystemCount, modelName);
    catch e
        fprintf('Warning: Error finding subsystems: %s\n', e.message);
        subsystems = {};
    end
end
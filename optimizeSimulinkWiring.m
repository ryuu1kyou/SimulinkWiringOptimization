function optimizeSimulinkWiring(modelName)
    try
        % モデルを開く
        hModel = load_system(modelName);
        modelBaseName = get_param(hModel, 'Name');

        % モデル内の全配線を最適化
        fprintf('Starting wiring optimization for model: %s\n', modelBaseName);

        % 特定のポートの配線を手動で最適化（人間が調整したレイアウトを参考に）
        fprintf('Applying manual optimization for specific ports...\n');
        manuallyOptimizeSpecificPorts(modelBaseName);

        % Simulinkの組み込み機能を使用して残りの配線を整理
        fprintf('Applying Simulink built-in routing for remaining wires...\n');
        useSimulinkBuiltInRouting(modelBaseName);

        % 現在の日時を取得して新しいファイル名を生成
        [filepath, name, ext] = fileparts(modelName);
        dt = datetime('now');
        timestamp = sprintf('%04d%02d%02d_%02d%02d%02d', ...
            dt.Year, dt.Month, dt.Day, dt.Hour, dt.Minute, round(dt.Second));
        newFileName = fullfile(filepath, sprintf('%s_%s%s', name, timestamp, ext));

        % 変更を新しいファイルとして保存
        save_system(modelBaseName, newFileName);
        fprintf('Optimized model saved as: %s\n', newFileName);

    catch e
        fprintf('Error: %s\n', e.message);
        fprintf('Stack trace: %s\n', getReport(e, 'extended'));
    end
end

function manuallyOptimizeSpecificPorts(modelName)
    % 特定のポートの配線を手動で最適化
    try
        % 特定のブロック名を検索
        specialBlocks = {'c_alfa', 'reff', 'delta', 'yVelo', 'Lf', 'yawRate'};

        for i = 1:length(specialBlocks)
            blockName = specialBlocks{i};
            fprintf('Looking for block: %s\n', blockName);

            % ブロックを検索
            blocks = find_system(modelName, 'FollowLinks', 'on', 'LookUnderMasks', 'all', 'Name', blockName);

            if ~isempty(blocks)
                for j = 1:length(blocks)
                    block = blocks{j};
                    fprintf('Optimizing wiring for block: %s\n', block);

                    % ブロックからの出力ラインを取得
                    outports = get_param(block, 'PortHandles');
                    if isfield(outports, 'Outport') && ~isempty(outports.Outport)
                        for k = 1:length(outports.Outport)
                            outport = outports.Outport(k);
                            lines = get_param(outport, 'Line');

                            if ~isempty(lines)
                                % 既存の配線を削除して再接続
                                reconstructWiring(block, outport, lines);
                            end
                        end
                    end
                end
            end
        end
    catch e
        fprintf('Error in manual optimization: %s\n', e.message);
    end
end

function reconstructWiring(sourceBlock, sourcePort, lineHandle)
    % 既存の配線を削除して、手動で最適化された配線を再構築
    try
        % ソースとデスティネーションの情報を取得
        srcPortNumber = get_param(sourcePort, 'PortNumber');
        dstPorts = get_param(lineHandle, 'DstPortHandle');

        if isempty(dstPorts) || all(dstPorts == -1)
            return;
        end

        % ソースの位置は使用しないため取得しない

        % デスティネーションの情報を収集
        dstInfo = cell(length(dstPorts), 1);
        for i = 1:length(dstPorts)
            if dstPorts(i) == -1
                continue;
            end

            dstBlock = get_param(dstPorts(i), 'Parent');
            dstPortNumber = get_param(dstPorts(i), 'PortNumber');
            dstPos = get_param(dstPorts(i), 'Position');

            dstInfo{i} = struct('Block', dstBlock, 'PortNumber', dstPortNumber, 'Position', dstPos);
        end

        % 既存の配線を削除
        delete_line(lineHandle);

        % ソースブロック名を取得
        srcBlockName = get_param(sourceBlock, 'Name');

        % 特定のブロックに対する特別な処理
        if strcmp(srcBlockName, 'c_alfa')
            optimizeCAlfaWiring(sourceBlock, srcPortNumber, dstInfo);
        elseif strcmp(srcBlockName, 'reff')
            optimizeReffWiring(sourceBlock, srcPortNumber, dstInfo);
        elseif strcmp(srcBlockName, 'delta') || strcmp(srcBlockName, 'yVelo') || ...
               strcmp(srcBlockName, 'Lf') || strcmp(srcBlockName, 'yawRate')
            optimizeLowerPortsWiring(sourceBlock, srcPortNumber, dstInfo);
        else
            % 通常の配線再接続
            for i = 1:length(dstInfo)
                if isempty(dstInfo{i})
                    continue;
                end

                % 新しい配線を追加（自動配線を使用）
                add_line(get_param(sourceBlock, 'Parent'), ...
                    [sourceBlock '/' num2str(srcPortNumber)], ...
                    [dstInfo{i}.Block '/' num2str(dstInfo{i}.PortNumber)], ...
                    'autorouting', 'on');
            end
        end
    catch e
        fprintf('Error reconstructing wiring: %s\n', e.message);

        % エラーが発生した場合、元の接続を復元
        try
            for i = 1:length(dstInfo)
                if isempty(dstInfo{i})
                    continue;
                end

                add_line(get_param(sourceBlock, 'Parent'), ...
                    [sourceBlock '/' num2str(srcPortNumber)], ...
                    [dstInfo{i}.Block '/' num2str(dstInfo{i}.PortNumber)], ...
                    'autorouting', 'on');
            end
        catch
            fprintf('Failed to restore original connections\n');
        end
    end
end

function optimizeCAlfaWiring(sourceBlock, srcPortNumber, dstInfo)
    % c_alfaブロックからの配線を最適化
    try
        % 親システムを取得
        parentSystem = get_param(sourceBlock, 'Parent');

        % ソースポートの位置を取得
        srcPortHandle = get_param([sourceBlock '/' num2str(srcPortNumber)], 'PortHandle');
        srcPos = get_param(srcPortHandle, 'Position');

        % 主要な分岐点の位置を計算
        mainBranchX = srcPos(1) + 60;

        % デスティネーションをY座標でソート
        dstPositions = zeros(length(dstInfo), 2);
        validDstInfo = cell(length(dstInfo), 1);
        validCount = 0;

        for i = 1:length(dstInfo)
            if ~isempty(dstInfo{i})
                validCount = validCount + 1;
                dstPositions(validCount, :) = dstInfo{i}.Position(1:2);
                validDstInfo{validCount} = dstInfo{i};
            end
        end

        dstPositions = dstPositions(1:validCount, :);
        validDstInfo = validDstInfo(1:validCount);

        % Y座標でソート
        [~, sortIndices] = sort(dstPositions(:, 2));

        % 上部、中部、下部のグループに分ける
        upperDstInfo = validDstInfo(sortIndices(1:ceil(validCount/3)));
        middleDstInfo = validDstInfo(sortIndices(ceil(validCount/3)+1:2*ceil(validCount/3)));
        lowerDstInfo = validDstInfo(sortIndices(2*ceil(validCount/3)+1:end));

        % 共通の垂直ライン位置
        commonVerticalX = mainBranchX + 80;

        % 上部グループの配線
        for i = 1:length(upperDstInfo)
            dstBlock = upperDstInfo{i}.Block;
            dstPortNumber = upperDstInfo{i}.PortNumber;
            dstPos = upperDstInfo{i}.Position;

            % 新しい配線を追加
            newLine = add_line(parentSystem, ...
                [sourceBlock '/' num2str(srcPortNumber)], ...
                [dstBlock '/' num2str(dstPortNumber)], ...
                'autorouting', 'smart');

            % 配線のポイントを設定
            points = [
                srcPos(1:2);
                mainBranchX, srcPos(2);
                mainBranchX, dstPos(2) - 20;
                commonVerticalX, dstPos(2) - 20;
                commonVerticalX, dstPos(2);
                dstPos(1:2)
            ];

            % 不要な点を削除
            points = removeRedundantPoints(points);

            % 配線を更新
            set_param(newLine, 'Points', points);
        end

        % 中部グループの配線
        for i = 1:length(middleDstInfo)
            dstBlock = middleDstInfo{i}.Block;
            dstPortNumber = middleDstInfo{i}.PortNumber;
            dstPos = middleDstInfo{i}.Position;

            % 新しい配線を追加
            newLine = add_line(parentSystem, ...
                [sourceBlock '/' num2str(srcPortNumber)], ...
                [dstBlock '/' num2str(dstPortNumber)], ...
                'autorouting', 'smart');

            % 配線のポイントを設定
            points = [
                srcPos(1:2);
                mainBranchX, srcPos(2);
                mainBranchX, dstPos(2);
                dstPos(1:2)
            ];

            % 不要な点を削除
            points = removeRedundantPoints(points);

            % 配線を更新
            set_param(newLine, 'Points', points);
        end

        % 下部グループの配線
        for i = 1:length(lowerDstInfo)
            dstBlock = lowerDstInfo{i}.Block;
            dstPortNumber = lowerDstInfo{i}.PortNumber;
            dstPos = lowerDstInfo{i}.Position;

            % 新しい配線を追加
            newLine = add_line(parentSystem, ...
                [sourceBlock '/' num2str(srcPortNumber)], ...
                [dstBlock '/' num2str(dstPortNumber)], ...
                'autorouting', 'smart');

            % 配線のポイントを設定
            points = [
                srcPos(1:2);
                mainBranchX, srcPos(2);
                mainBranchX, dstPos(2) + 20;
                commonVerticalX, dstPos(2) + 20;
                commonVerticalX, dstPos(2);
                dstPos(1:2)
            ];

            % 不要な点を削除
            points = removeRedundantPoints(points);

            % 配線を更新
            set_param(newLine, 'Points', points);
        end
    catch e
        fprintf('Error optimizing c_alfa wiring: %s\n', e.message);
        rethrow(e);
    end
end

function optimizeReffWiring(sourceBlock, srcPortNumber, dstInfo)
    % reffブロックからの配線を最適化
    try
        % 親システムを取得
        parentSystem = get_param(sourceBlock, 'Parent');

        % ソースポートの位置を取得
        srcPortHandle = get_param([sourceBlock '/' num2str(srcPortNumber)], 'PortHandle');
        srcPos = get_param(srcPortHandle, 'Position');

        % 主要な分岐点の位置を計算
        mainBranchX = srcPos(1) + 50;

        % デスティネーションをY座標でソート
        dstPositions = zeros(length(dstInfo), 2);
        validDstInfo = cell(length(dstInfo), 1);
        validCount = 0;

        for i = 1:length(dstInfo)
            if ~isempty(dstInfo{i})
                validCount = validCount + 1;
                dstPositions(validCount, :) = dstInfo{i}.Position(1:2);
                validDstInfo{validCount} = dstInfo{i};
            end
        end

        dstPositions = dstPositions(1:validCount, :);
        validDstInfo = validDstInfo(1:validCount);

        % Y座標でソート
        [~, sortIndices] = sort(dstPositions(:, 2));

        % 各デスティネーションへの配線
        for i = 1:length(validDstInfo)
            idx = sortIndices(i);
            dstBlock = validDstInfo{idx}.Block;
            dstPortNumber = validDstInfo{idx}.PortNumber;
            dstPos = validDstInfo{idx}.Position;

            % 新しい配線を追加
            newLine = add_line(parentSystem, ...
                [sourceBlock '/' num2str(srcPortNumber)], ...
                [dstBlock '/' num2str(dstPortNumber)], ...
                'autorouting', 'smart');

            % 配線のポイントを設定
            points = [
                srcPos(1:2);
                mainBranchX, srcPos(2);
                mainBranchX, dstPos(2);
                dstPos(1:2)
            ];

            % 不要な点を削除
            points = removeRedundantPoints(points);

            % 配線を更新
            set_param(newLine, 'Points', points);
        end
    catch e
        fprintf('Error optimizing reff wiring: %s\n', e.message);
        rethrow(e);
    end
end

function optimizeLowerPortsWiring(sourceBlock, srcPortNumber, dstInfo)
    % 下部ポート（delta, yVelo, Lf, yawRate）からの配線を最適化
    try
        % 親システムを取得
        parentSystem = get_param(sourceBlock, 'Parent');

        % ソースポートの位置を取得
        srcPortHandle = get_param([sourceBlock '/' num2str(srcPortNumber)], 'PortHandle');
        srcPos = get_param(srcPortHandle, 'Position');

        % 主要な分岐点の位置を計算
        mainBranchX = srcPos(1) + 40;

        % デスティネーションの情報を収集
        validDstInfo = cell(length(dstInfo), 1);
        validCount = 0;

        for i = 1:length(dstInfo)
            if ~isempty(dstInfo{i})
                validCount = validCount + 1;
                validDstInfo{validCount} = dstInfo{i};
            end
        end

        % 実際に使用したサイズに切り詰める
        validDstInfo = validDstInfo(1:validCount);

        % 各デスティネーションへの配線
        for i = 1:length(validDstInfo)
            dstBlock = validDstInfo{i}.Block;
            dstPortNumber = validDstInfo{i}.PortNumber;
            dstPos = validDstInfo{i}.Position;

            % 新しい配線を追加
            newLine = add_line(parentSystem, ...
                [sourceBlock '/' num2str(srcPortNumber)], ...
                [dstBlock '/' num2str(dstPortNumber)], ...
                'autorouting', 'smart');

            % 配線のポイントを設定
            points = [
                srcPos(1:2);
                mainBranchX, srcPos(2);
                mainBranchX, dstPos(2);
                dstPos(1:2)
            ];

            % 不要な点を削除
            points = removeRedundantPoints(points);

            % 配線を更新
            set_param(newLine, 'Points', points);
        end
    catch e
        fprintf('Error optimizing lower ports wiring: %s\n', e.message);
        rethrow(e);
    end
end

function useSimulinkBuiltInRouting(modelName)
    % すべてのサブシステムを取得
    allSystems = find_system(modelName, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', 'SubSystem');
    allSystems = [{modelName}; allSystems];

    % 処理したサブシステムの数を追跡
    totalSystems = length(allSystems);
    fprintf('Found %d systems/subsystems to process\n', totalSystems);

    % エラーカウンタ
    errorCount = 0;
    successCount = 0;

    for i = 1:totalSystems
        currentSystem = allSystems{i};

        % 進捗状況を表示（10%ごと）
        if mod(i, max(1, round(totalSystems/10))) == 0
            fprintf('Processing: %d%% complete (%d/%d systems)\n', ...
                round(i/totalSystems*100), i, totalSystems);
        end

        try
            % システム内の全ラインを取得
            lines = find_system(currentSystem, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'Line');

            if ~isempty(lines)
                % 分岐点の最適化を先に実行
                try
                    fprintf('Optimizing branch points in %s...\n', currentSystem);
                    optimizeBranchPoints(currentSystem, lines);
                catch branchE
                    fprintf('Warning: Failed to optimize branch points: %s\n', branchE.message);
                end

                % Simulinkの組み込み機能を使用して配線を整理
                % 注意: この関数はSimulink R2016b以降で使用可能
                Simulink.BlockDiagram.routeLine(lines);
                fprintf('Successfully routed %d lines in %s\n', length(lines), currentSystem);
                successCount = successCount + 1;
            end
        catch e
            errorCount = errorCount + 1;
            fprintf('Warning: Error processing system %s: %s\n', currentSystem, e.message);

            % エラーが多すぎる場合は詳細なデバッグ情報を表示
            if errorCount <= 10 || mod(errorCount, 50) == 0
                fprintf('  - Error details: %s\n', getReport(e, 'basic'));
            end

            % 別の方法を試す
            try
                fprintf('Trying alternative method for %s...\n', currentSystem);
                routeUsingAutoLayout(currentSystem);
                successCount = successCount + 1;
            catch altE
                fprintf('Alternative method also failed: %s\n', altE.message);
            end
        end
    end

    % 処理結果の要約を表示
    fprintf('\nOptimization complete:\n');
    fprintf('  - Successfully processed: %d systems\n', successCount);
    fprintf('  - Errors encountered: %d\n', errorCount);

    % 最後に全体の配線を再度最適化
    try
        fprintf('Performing final optimization on the entire model...\n');
        allLines = find_system(modelName, 'FindAll', 'on', 'Type', 'Line');
        if ~isempty(allLines)
            Simulink.BlockDiagram.routeLine(allLines);
        end
    catch finalE
        fprintf('Warning: Final optimization failed: %s\n', finalE.message);
    end
end

function routeUsingAutoLayout(systemName)
    % システム内の全ラインを取得
    lines = find_system(systemName, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'Line');

    if isempty(lines)
        return;
    end

    % 同じソースから複数のデスティネーションへの配線を最適化
    try
        optimizeBranchPoints(systemName, lines);
    catch
        % エラーが発生しても続行
    end

    % 各ラインを処理
    for i = 1:length(lines)
        try
            lineHandle = lines(i);
            if ~ishandle(lineHandle) || ~strcmp(get_param(lineHandle, 'Type'), 'line')
                continue;
            end

            % ソースとデスティネーションの情報を取得
            srcPort = get_param(lineHandle, 'SrcPortHandle');
            dstPorts = get_param(lineHandle, 'DstPortHandle');

            if srcPort == -1 || isempty(dstPorts) || all(dstPorts == -1)
                continue;
            end

            % 自動配線を適用
            set_param(lineHandle, 'autorouting', 'on');
        catch e
            fprintf('Warning: Failed to route line: %s\n', e.message);
        end
    end

    % 自動レイアウトを適用（可能な場合）
    try
        % 注意: この関数はSimulink R2016b以降で使用可能
        Simulink.BlockDiagram.arrangeSystem(systemName);
    catch e
        fprintf('Warning: Failed to arrange system %s: %s\n', systemName, e.message);
    end
end

function optimizeBranchPoints(systemName, lines)
    % ソースポートごとに配線をグループ化
    sourceGroups = containers.Map('KeyType', 'double', 'ValueType', 'any');

    for i = 1:length(lines)
        try
            lineHandle = lines(i);
            if ~ishandle(lineHandle) || ~strcmp(get_param(lineHandle, 'Type'), 'line')
                continue;
            end

            % ソースポートを取得
            srcPort = get_param(lineHandle, 'SrcPortHandle');
            if srcPort == -1
                continue;
            end

            % ソースポートをキーとして配線をグループ化
            if ~sourceGroups.isKey(srcPort)
                sourceGroups(srcPort) = [];
            end
            sourceGroups(srcPort) = [sourceGroups(srcPort), lineHandle];
        catch
            continue;
        end
    end

    % 各グループの配線を最適化
    keys = sourceGroups.keys;
    for i = 1:length(keys)
        srcPort = keys{i};
        groupLines = sourceGroups(srcPort);

        % 3本以上の配線がある場合のみ最適化
        if length(groupLines) >= 3
            try
                optimizeSourceGroup(systemName, srcPort, groupLines);
            catch e
                fprintf('Warning: Failed to optimize branch points for source %d: %s\n', srcPort, e.message);
            end
        end
    end
end

function optimizeSourceGroup(~, srcPort, groupLines)
    % ソースの位置を取得
    srcPos = get_param(srcPort, 'Position');
    srcBlockHandle = get_param(srcPort, 'Parent');

    % ソースブロックの名前を取得（特別な処理のため）
    try
        srcBlockName = get_param(srcBlockHandle, 'Name');
    catch
        srcBlockName = '';
    end

    % 分岐点の位置を計算（ソースから少し離れた位置）
    branchX = srcPos(1) + 30;  % ソースから30ピクセル右
    branchY = srcPos(2);       % ソースと同じY座標

    % デスティネーションの位置を収集して分析
    % 事前に配列を確保（最大サイズで）
    dstPositions = zeros(length(groupLines), 2);
    dstBlocks = cell(length(groupLines), 1);
    validLines = zeros(1, length(groupLines));
    validCount = 0;

    for i = 1:length(groupLines)
        try
            lineHandle = groupLines(i);
            dstPorts = get_param(lineHandle, 'DstPortHandle');

            if isempty(dstPorts) || dstPorts(1) == -1
                continue;
            end

            % デスティネーションの位置とブロック情報を取得
            dstPos = get_param(dstPorts(1), 'Position');
            dstBlockHandle = get_param(dstPorts(1), 'Parent');

            validCount = validCount + 1;
            dstPositions(validCount, :) = dstPos(1:2);
            dstBlocks{validCount} = dstBlockHandle;
            validLines(validCount) = lineHandle;
        catch
            continue;
        end
    end

    % 実際に使用したサイズに切り詰める
    dstPositions = dstPositions(1:validCount, :);
    dstBlocks = dstBlocks(1:validCount);
    validLines = validLines(1:validCount);

    % 有効な配線がない場合は終了
    if isempty(validLines)
        return;
    end

    % 特定のポート（ポート4, 5など）に対する特別な処理
    isSpecialPort = false;
    try
        if strcmp(srcBlockName, 'c_alfa') || strcmp(srcBlockName, 'reff')
            isSpecialPort = true;
        end
    catch
        % エラーが発生した場合は通常処理を続行
    end

    % 特別な処理が必要なポートの場合
    if isSpecialPort && validCount > 2
        optimizeSpecialPortWiring(srcPos, dstPositions, dstBlocks, validLines);
        return;
    end

    % Y座標でグループ化（同じ高さのデスティネーション）
    [uniqueYs, ~, yIndices] = unique(dstPositions(:,2));

    % 各Y座標グループに対して最適な分岐点を設定
    for i = 1:length(uniqueYs)
        % このY座標を持つデスティネーションのインデックスを取得
        groupIndices = find(yIndices == i);

        if length(groupIndices) > 1
            % このグループの最も左のX座標を見つける
            minX = min(dstPositions(groupIndices, 1));

            % このグループ用の分岐点を設定（最も左のX座標より少し左）
            groupBranchX = max(branchX, minX - 30);
            groupBranchY = uniqueYs(i);

            % このグループの各配線を処理
            for j = 1:length(groupIndices)
                idx = groupIndices(j);
                lineHandle = validLines(idx);
                dstPos = dstPositions(idx, :);

                % 配線のポイントを生成
                points = [
                    srcPos(1:2);                    % ソース
                    branchX, branchY;               % 最初の分岐点
                    branchX, groupBranchY;          % 垂直移動
                    groupBranchX, groupBranchY;     % 水平移動（グループの分岐点）
                    dstPos                          % デスティネーション
                ];

                % 不要な点を削除
                points = removeRedundantPoints(points);

                % 配線を更新
                set_param(lineHandle, 'Points', points);
            end
        else
            % 単一のデスティネーションの場合は直接接続
            lineHandle = validLines(groupIndices);
            dstPos = dstPositions(groupIndices, :);

            % 配線のポイントを生成
            points = [
                srcPos(1:2);                % ソース
                branchX, branchY;           % 分岐点
                branchX, dstPos(2);         % 垂直移動
                dstPos                      % デスティネーション
            ];

            % 不要な点を削除
            points = removeRedundantPoints(points);

            % 配線を更新
            set_param(lineHandle, 'Points', points);
        end
    end
end

function optimizeSpecialPortWiring(srcPos, dstPositions, ~, validLines)
    % ポート4（c_alfa）とポート5（reff）のような特別なポートの配線を最適化
    % これらのポートは複数の分岐点を持ち、特別な処理が必要

    % 主要な分岐点の位置を計算（人間が調整したレイアウトを参考に）
    mainBranchX = srcPos(1) + 50;  % ソースから少し離れた位置
    mainBranchY = srcPos(2);       % ソースと同じY座標

    % デスティネーションをY座標でソート
    [~, sortIndices] = sort(dstPositions(:,2));

    % デスティネーションの位置を分析
    numDest = length(sortIndices);

    % デスティネーションをグループ化（人間が調整したレイアウトを参考に）
    % 事前に配列を確保
    upperDestIndices = zeros(1, numDest);
    middleDestIndices = zeros(1, numDest);
    lowerDestIndices = zeros(1, numDest);
    upperCount = 0;
    middleCount = 0;
    lowerCount = 0;

    % デスティネーションの位置に基づいてグループ分け
    for i = 1:numDest
        idx = sortIndices(i);
        dstY = dstPositions(idx, 2);

        % Y座標に基づいてグループ分け
        if dstY < srcPos(2) - 50  % 上部グループ
            upperCount = upperCount + 1;
            upperDestIndices(upperCount) = idx;
        elseif dstY > srcPos(2) + 100  % 下部グループ
            lowerCount = lowerCount + 1;
            lowerDestIndices(lowerCount) = idx;
        else  % 中部グループ
            middleCount = middleCount + 1;
            middleDestIndices(middleCount) = idx;
        end
    end

    % 実際に使用したサイズに切り詰める
    upperDestIndices = upperDestIndices(1:upperCount);
    middleDestIndices = middleDestIndices(1:middleCount);
    lowerDestIndices = lowerDestIndices(1:lowerCount);

    % 各グループの共通Y座標を設定（人間が調整したレイアウトを参考に）
    if ~isempty(upperDestIndices)
        upperBranchY = min(dstPositions(upperDestIndices, 2)) - 10;
    else
        upperBranchY = srcPos(2) - 60;
    end

    % 中部グループは個別に処理するため共通Y座標は不要

    if ~isempty(lowerDestIndices)
        lowerBranchY = max(dstPositions(lowerDestIndices, 2)) + 10;
    else
        lowerBranchY = srcPos(2) + 60;
    end

    % 各グループの共通X座標を設定（人間が調整したレイアウトを参考に）
    commonBranchX = mainBranchX + 80;  % すべてのグループで共通の垂直ライン

    % 上部グループの配線を処理
    for i = 1:length(upperDestIndices)
        idx = upperDestIndices(i);
        lineHandle = validLines(idx);
        dstPos = dstPositions(idx, :);

        % 人間が調整したレイアウトを参考にした配線ポイント
        points = [
            srcPos(1:2);                    % ソース
            mainBranchX, mainBranchY;       % メイン分岐点
            mainBranchX, upperBranchY;      % 垂直移動
            commonBranchX, upperBranchY;    % 水平移動（共通垂直ライン）
            commonBranchX, dstPos(2);       % 垂直移動
            dstPos                          % デスティネーション
        ];

        points = removeRedundantPoints(points);
        set_param(lineHandle, 'Points', points);
    end

    % 中部グループの配線を処理
    for i = 1:length(middleDestIndices)
        idx = middleDestIndices(i);
        lineHandle = validLines(idx);
        dstPos = dstPositions(idx, :);

        % 人間が調整したレイアウトを参考にした配線ポイント
        % 中部グループは直接接続（分岐点を最小限に）
        points = [
            srcPos(1:2);                    % ソース
            mainBranchX, mainBranchY;       % メイン分岐点
            mainBranchX, dstPos(2);         % 垂直移動（直接デスティネーションの高さへ）
            dstPos                          % デスティネーション
        ];

        points = removeRedundantPoints(points);
        set_param(lineHandle, 'Points', points);
    end

    % 下部グループの配線を処理
    for i = 1:length(lowerDestIndices)
        idx = lowerDestIndices(i);
        lineHandle = validLines(idx);
        dstPos = dstPositions(idx, :);

        % 人間が調整したレイアウトを参考にした配線ポイント
        points = [
            srcPos(1:2);                    % ソース
            mainBranchX, mainBranchY;       % メイン分岐点
            mainBranchX, lowerBranchY;      % 垂直移動
            commonBranchX, lowerBranchY;    % 水平移動（共通垂直ライン）
            commonBranchX, dstPos(2);       % 垂直移動
            dstPos                          % デスティネーション
        ];

        points = removeRedundantPoints(points);
        set_param(lineHandle, 'Points', points);
    end
end

function points = removeRedundantPoints(points)
    % 3点が一直線上にある場合、中間点を削除
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
end

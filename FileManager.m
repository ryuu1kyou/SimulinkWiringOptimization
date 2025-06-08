classdef FileManager < handle
    % FILEMANAGER ファイル操作を管理するクラス
    %
    % このクラスは、Simulinkモデルファイルの読み込み、保存、バックアップ、
    % 画像出力などのファイル操作を一元管理します。
    
    properties (Access = private)
        config_         % OptimizationConfigオブジェクト
        loadedModels_   % 読み込み済みモデルのリスト
    end
    
    methods
        function obj = FileManager(config)
            % コンストラクタ
            %
            % 入力:
            %   config - OptimizationConfigオブジェクト
            
            if nargin < 1 || ~isa(config, 'OptimizationConfig')
                error('FileManager:InvalidConfig', 'OptimizationConfigオブジェクトが必要です');
            end
            
            obj.config_ = config;
            obj.loadedModels_ = {};
        end
        
        function success = createBackup(obj, modelName)
            % モデルのバックアップを作成
            %
            % 入力:
            %   modelName - モデルファイルのパス
            %
            % 出力:
            %   success - バックアップ作成の成功/失敗
            
            success = false;
            
            try
                if ~exist(modelName, 'file')
                    error('モデルファイルが見つかりません: %s', modelName);
                end
                
                [~, baseName, ext] = fileparts(modelName);
                backupName = sprintf('%s_backup%s', baseName, ext);
                
                if ~exist(backupName, 'file')
                    copyfile(modelName, backupName);
                    if obj.config_.verbose
                        fprintf('バックアップファイルを作成: %s\n', backupName);
                    end
                else
                    if obj.config_.verbose
                        fprintf('バックアップファイルが既に存在: %s\n', backupName);
                    end
                end
                
                success = true;
                
            catch ME
                warning('FileManager:BackupFailed', ...
                    'バックアップの作成に失敗: %s', ME.message);
            end
        end
        
        function [success, modelBaseName] = loadModel(obj, modelName)
            % Simulinkモデルを読み込み
            %
            % 入力:
            %   modelName - モデルファイルのパス
            %
            % 出力:
            %   success - 読み込みの成功/失敗
            %   modelBaseName - モデルのベース名（拡張子なし）

            success = false;
            modelBaseName = '';

            try
                if obj.config_.verbose
                    fprintf('FileManager.loadModel: モデル読み込み開始: %s\n', modelName);
                end

                if ~exist(modelName, 'file')
                    error('モデルファイルが見つかりません: %s', modelName);
                end

                [~, modelBaseName, ~] = fileparts(modelName);

                if obj.config_.verbose
                    fprintf('FileManager.loadModel: modelBaseName = "%s"\n', modelBaseName);
                end

                % モデルが既に読み込まれているかチェック
                if bdIsLoaded(modelBaseName)
                    if obj.config_.verbose
                        fprintf('モデルは既に読み込まれています: %s\n', modelBaseName);
                    end
                else
                    if obj.config_.verbose
                        fprintf('load_system実行中: %s\n', modelName);
                    end
                    load_system(modelName);
                    if obj.config_.verbose
                        fprintf('モデルを読み込みました: %s\n', modelBaseName);
                    end
                end

                % 読み込み済みリストに追加
                if ~ismember(modelBaseName, obj.loadedModels_)
                    obj.loadedModels_{end+1} = modelBaseName;
                end

                success = true;

                if obj.config_.verbose
                    fprintf('FileManager.loadModel: 成功 - success=%s, modelBaseName="%s"\n', ...
                        mat2str(success), modelBaseName);
                end

            catch ME
                if obj.config_.verbose
                    fprintf('FileManager.loadModel: エラー発生: %s\n', ME.message);
                    fprintf('スタックトレース:\n');
                    for i = 1:length(ME.stack)
                        fprintf('  %s (行 %d)\n', ME.stack(i).name, ME.stack(i).line);
                    end
                end
                % エラーを再スローせずに、失敗を示すフラグを返す
                success = false;
                modelBaseName = '';
            end
        end
        
        function success = saveOptimizedModel(obj, modelBaseName, suffix)
            % 最適化されたモデルを保存
            %
            % 入力:
            %   modelBaseName - モデルのベース名
            %   suffix - ファイル名に追加するサフィックス（オプション）
            %
            % 出力:
            %   success - 保存の成功/失敗
            
            if nargin < 3
                timestamp = datestr(now, 'yyyymmdd_HHMMSS');
                suffix = sprintf('optimized_%s', timestamp);
            end
            
            success = false;
            
            try
                optimizedModelName = sprintf('%s_%s.slx', modelBaseName, suffix);
                save_system(modelBaseName, optimizedModelName);
                
                if obj.config_.verbose
                    fprintf('最適化されたモデルを保存: %s\n', optimizedModelName);
                end
                
                success = true;
                
            catch ME
                warning('FileManager:SaveFailed', ...
                    'モデルの保存に失敗: %s', ME.message);
            end
        end
        
        function success = ensureOutputDirectory(obj, dirName)
            % 出力ディレクトリの存在を確認し、必要に応じて作成
            %
            % 入力:
            %   dirName - ディレクトリ名（オプション、デフォルトは設定から取得）
            
            if nargin < 2
                dirName = obj.config_.outputDirectory;
            end
            
            success = false;
            
            try
                if ~exist(dirName, 'dir')
                    mkdir(dirName);
                    if obj.config_.verbose
                        fprintf('出力ディレクトリを作成: %s\n', dirName);
                    end
                end
                
                success = true;
                
            catch ME
                warning('FileManager:DirectoryCreationFailed', ...
                    'ディレクトリの作成に失敗: %s', ME.message);
            end
        end
        
        function success = saveModelImage(obj, systemName, outputPath, imageFormat)
            % モデルまたはサブシステムの画像を保存
            %
            % 入力:
            %   systemName - システム名
            %   outputPath - 出力パス
            %   imageFormat - 画像フォーマット（オプション、デフォルト: 'png'）
            
            if nargin < 4
                imageFormat = 'png';
            end
            
            success = false;
            
            try
                if obj.config_.verbose
                    fprintf('      画像保存中: %s -> %s\n', systemName, outputPath);
                end
                
                % システムを開く（表示）
                open_system(systemName);
                
                % 少し待機してレンダリングを完了
                pause(0.5);
                
                % 画像として保存
                try
                    % 高解像度で保存
                    print(systemName, sprintf('-d%s', imageFormat), '-r150', outputPath);
                catch
                    % printが失敗した場合はsaveasを試行
                    saveas(get_param(systemName, 'Handle'), outputPath, imageFormat);
                end
                
                if obj.config_.verbose
                    fprintf('      画像保存完了: %s\n', outputPath);
                end
                
                success = true;
                
            catch ME
                warning('FileManager:ImageSaveFailed', ...
                    '画像保存に失敗: %s', ME.message);
            end
        end
        
        function imagePath = generateImagePath(obj, systemName, suffix, imageFormat)
            % 画像パスを生成
            %
            % 入力:
            %   systemName - システム名
            %   suffix - ファイル名サフィックス
            %   imageFormat - 画像フォーマット（オプション、デフォルト: 'png'）
            
            if nargin < 4
                imageFormat = 'png';
            end
            
            % システム名からファイル名を生成
            [~, baseName, ~] = fileparts(systemName);
            if contains(systemName, '/')
                % サブシステムの場合、パスの区切り文字を置換
                baseName = strrep(systemName, '/', '_');
            end
            
            fileName = sprintf('%s_%s.%s', baseName, suffix, imageFormat);
            imagePath = fullfile(obj.config_.outputDirectory, fileName);
        end
        
        function cleanup(obj)
            % リソースのクリーンアップ
            
            if obj.config_.verbose && ~isempty(obj.loadedModels_)
                fprintf('読み込み済みモデル: %s\n', strjoin(obj.loadedModels_, ', '));
            end
            
            % 必要に応じて、読み込んだモデルを閉じる処理を追加
            % （通常は手動で閉じることが多いため、ここではリストのクリアのみ）
            obj.loadedModels_ = {};
        end
        
        function models = getLoadedModels(obj)
            % 読み込み済みモデルのリストを取得
            models = obj.loadedModels_;
        end
        
        function exists = modelExists(obj, modelName)
            % モデルファイルの存在確認
            exists = exist(modelName, 'file') == 4; % 4 = Simulink model file
        end
        
        function loaded = isModelLoaded(obj, modelBaseName)
            % モデルが読み込まれているかチェック
            loaded = bdIsLoaded(modelBaseName);
        end
        
        function success = closeModel(obj, modelBaseName, saveChanges)
            % モデルを閉じる
            %
            % 入力:
            %   modelBaseName - モデルのベース名
            %   saveChanges - 変更を保存するか（オプション、デフォルト: false）
            
            if nargin < 3
                saveChanges = false;
            end
            
            success = false;
            
            try
                if obj.isModelLoaded(modelBaseName)
                    if saveChanges
                        save_system(modelBaseName);
                    end
                    
                    close_system(modelBaseName, 0); % 0 = don't save
                    
                    % リストから削除
                    obj.loadedModels_ = obj.loadedModels_(~strcmp(obj.loadedModels_, modelBaseName));
                    
                    if obj.config_.verbose
                        fprintf('モデルを閉じました: %s\n', modelBaseName);
                    end
                    
                    success = true;
                end
                
            catch ME
                warning('FileManager:CloseModelFailed', ...
                    'モデルを閉じるのに失敗: %s', ME.message);
            end
        end
        
        function fileList = listFilesInDirectory(obj, dirPath, extension)
            % ディレクトリ内のファイルをリスト
            %
            % 入力:
            %   dirPath - ディレクトリパス
            %   extension - ファイル拡張子（オプション）
            
            if nargin < 3
                extension = '*';
            end
            
            fileList = {};
            
            try
                if exist(dirPath, 'dir')
                    pattern = fullfile(dirPath, sprintf('*.%s', extension));
                    files = dir(pattern);
                    fileList = {files.name};
                end
                
            catch ME
                warning('FileManager:ListFilesFailed', ...
                    'ファイルリストの取得に失敗: %s', ME.message);
            end
        end
    end
end

classdef OptimizationConfig < handle
    % OPTIMIZATIONCONFIG 配線最適化の設定を管理するクラス
    %
    % このクラスは、Simulink配線最適化プロセスの全ての設定パラメータを
    % 一元管理し、設定の検証と更新を行います。
    
    properties (Access = private)
        preserveLines_      % 既存の線を保持するか
        enableAIEvaluation_ % AI評価機能を有効にするか
        targetSubsystem_   % 対象サブシステム
        wiringParams_      % 配線パラメータ
        outputDirectory_   % 出力ディレクトリ
        verbose_           % 詳細出力モード
    end

    properties (Dependent)
        preserveLines
        enableAIEvaluation
        targetSubsystem
        wiringParams
        outputDirectory
        verbose
    end
    
    methods
        function obj = OptimizationConfig(varargin)
            % コンストラクタ - デフォルト設定で初期化
            
            % デフォルト値の設定
            obj.preserveLines_ = true;
            obj.enableAIEvaluation_ = true;
            obj.targetSubsystem_ = '';
            obj.outputDirectory_ = 'optimization_images';
            obj.verbose_ = true;
            
            % デフォルト配線パラメータ
            obj.wiringParams_ = struct(...
                'baseOffset', 10, ...
                'maxOffset', 50, ...
                'commonXOffset', 50, ...
                'scaleFactor', 0.5, ...
                'minSpacing', 15, ...
                'tolerance', 1e-6, ...
                'maxIterations', 100 ...
            );
            
            % 入力パラメータの処理
            if nargin > 0
                obj.parseInputArguments(varargin{:});
            end
            
            obj.validateConfiguration();
        end
        
        function parseInputArguments(obj, varargin)
            % 入力引数を解析して設定を更新
            
            p = inputParser;
            addParameter(p, 'preserveLines', obj.preserveLines_, @islogical);
            addParameter(p, 'enableAIEvaluation', obj.enableAIEvaluation_, @islogical);
            addParameter(p, 'targetSubsystem', obj.targetSubsystem_, @ischar);
            addParameter(p, 'outputDirectory', obj.outputDirectory_, @ischar);
            addParameter(p, 'verbose', obj.verbose_, @islogical);
            addParameter(p, 'wiringParams', struct(), @isstruct);

            parse(p, varargin{:});

            % 設定を更新
            obj.preserveLines_ = p.Results.preserveLines;
            obj.enableAIEvaluation_ = p.Results.enableAIEvaluation;
            obj.targetSubsystem_ = p.Results.targetSubsystem;
            obj.outputDirectory_ = p.Results.outputDirectory;
            obj.verbose_ = p.Results.verbose;
            
            % 配線パラメータのマージ
            if ~isempty(fieldnames(p.Results.wiringParams))
                obj.mergeWiringParams(p.Results.wiringParams);
            end
        end
        
        function mergeWiringParams(obj, newParams)
            % 新しい配線パラメータを既存のものとマージ
            
            fields = fieldnames(newParams);
            for i = 1:length(fields)
                field = fields{i};
                if isfield(obj.wiringParams_, field)
                    obj.wiringParams_.(field) = newParams.(field);
                else
                    warning('OptimizationConfig:UnknownParameter', ...
                        '未知の配線パラメータ: %s', field);
                end
            end
        end
        
        function validateConfiguration(obj)
            % 設定の妥当性を検証
            
            % 出力ディレクトリの検証
            if isempty(obj.outputDirectory_)
                obj.outputDirectory_ = 'optimization_images';
            end
            
            % 配線パラメータの検証
            requiredFields = {'baseOffset', 'maxOffset', 'commonXOffset', ...
                             'scaleFactor', 'minSpacing', 'tolerance', 'maxIterations'};
            
            for i = 1:length(requiredFields)
                field = requiredFields{i};
                if ~isfield(obj.wiringParams_, field)
                    error('OptimizationConfig:MissingParameter', ...
                        '必須の配線パラメータが不足: %s', field);
                end
                
                value = obj.wiringParams_.(field);
                if ~isnumeric(value) || ~isscalar(value) || value < 0
                    error('OptimizationConfig:InvalidParameter', ...
                        '無効な配線パラメータ値: %s = %s', field, mat2str(value));
                end
            end
        end
        
        function displayConfiguration(obj)
            % 現在の設定を表示
            
            fprintf('=== 配線最適化設定 ===\n');
            fprintf('既存線保持: %s\n', mat2str(obj.preserveLines_));
            fprintf('AI評価機能: %s\n', mat2str(obj.enableAIEvaluation_));
            fprintf('対象サブシステム: %s\n', obj.getTargetDisplayName());
            fprintf('出力ディレクトリ: %s\n', obj.outputDirectory_);
            fprintf('詳細出力: %s\n', mat2str(obj.verbose_));
            
            fprintf('\n--- 配線パラメータ ---\n');
            fields = fieldnames(obj.wiringParams_);
            for i = 1:length(fields)
                field = fields{i};
                value = obj.wiringParams_.(field);
                fprintf('%s: %g\n', field, value);
            end
            fprintf('=====================\n\n');
        end
        
        function name = getTargetDisplayName(obj)
            % 対象の表示名を取得
            if isempty(obj.targetSubsystem_)
                name = 'モデル全体';
            else
                name = obj.targetSubsystem_;
            end
        end
        
        function config = toStruct(obj)
            % 設定を構造体として取得
            config = struct();
            config.preserveLines = obj.preserveLines_;
            config.enableAIEvaluation = obj.enableAIEvaluation_;
            config.targetSubsystem = obj.targetSubsystem_;
            config.outputDirectory = obj.outputDirectory_;
            config.verbose = obj.verbose_;
            config.wiringParams = obj.wiringParams_;
        end
        
        function loadFromStruct(obj, config)
            % 構造体から設定を読み込み
            if isfield(config, 'preserveLines')
                obj.preserveLines_ = config.preserveLines;
            end
            if isfield(config, 'enableAIEvaluation')
                obj.enableAIEvaluation_ = config.enableAIEvaluation;
            end
            if isfield(config, 'targetSubsystem')
                obj.targetSubsystem_ = config.targetSubsystem;
            end
            if isfield(config, 'outputDirectory')
                obj.outputDirectory_ = config.outputDirectory;
            end
            if isfield(config, 'verbose')
                obj.verbose_ = config.verbose;
            end
            if isfield(config, 'wiringParams')
                obj.wiringParams_ = config.wiringParams;
            end
            
            obj.validateConfiguration();
        end
    end
    
    % Dependent properties のgetter/setter
    methods
        function value = get.preserveLines(obj)
            value = obj.preserveLines_;
        end
        
        function set.preserveLines(obj, value)
            validateattributes(value, {'logical'}, {'scalar'});
            obj.preserveLines_ = value;
        end
        
        function value = get.enableAIEvaluation(obj)
            value = obj.enableAIEvaluation_;
        end

        function set.enableAIEvaluation(obj, value)
            validateattributes(value, {'logical'}, {'scalar'});
            obj.enableAIEvaluation_ = value;
        end
        
        function value = get.targetSubsystem(obj)
            value = obj.targetSubsystem_;
        end
        
        function set.targetSubsystem(obj, value)
            validateattributes(value, {'char'}, {});
            obj.targetSubsystem_ = value;
        end
        
        function value = get.wiringParams(obj)
            value = obj.wiringParams_;
        end
        
        function set.wiringParams(obj, value)
            validateattributes(value, {'struct'}, {});
            obj.wiringParams_ = value;
            obj.validateConfiguration();
        end
        
        function value = get.outputDirectory(obj)
            value = obj.outputDirectory_;
        end
        
        function set.outputDirectory(obj, value)
            validateattributes(value, {'char'}, {});
            obj.outputDirectory_ = value;
        end
        
        function value = get.verbose(obj)
            value = obj.verbose_;
        end
        
        function set.verbose(obj, value)
            validateattributes(value, {'logical'}, {'scalar'});
            obj.verbose_ = value;
        end
    end
end

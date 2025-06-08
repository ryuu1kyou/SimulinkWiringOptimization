classdef SimulinkBlock < handle
    % SIMULINKBLOCK Simulinkブロックを表現するクラス
    %
    % このクラスは、Simulinkブロックのハンドルをラップし、
    % レイアウト分析と配線最適化に必要な操作を提供します。
    
    properties (Access = private)
        handle_         % Simulinkブロックハンドル
        name_           % ブロック名
        fullName_       % フルパス名
        position_       % ブロック位置 [left top right bottom]
        blockType_      % ブロックタイプ
        orientation_    % ブロックの向き
        inputPorts_     % 入力ポート情報
        outputPorts_    % 出力ポート情報
    end
    
    properties (Dependent)
        handle
        name
        fullName
        position
        blockType
        orientation
        inputPorts
        outputPorts
        center
        width
        height
    end
    
    methods
        function obj = SimulinkBlock(blockPath)
            % コンストラクタ
            %
            % 入力:
            %   blockPath - ブロックのパスまたはハンドル
            
            if nargin < 1
                error('SimulinkBlock:InvalidInput', 'ブロックパスまたはハンドルが必要です');
            end
            
            if ischar(blockPath)
                % パスから情報を取得
                obj.fullName_ = blockPath;
                try
                    obj.handle_ = get_param(blockPath, 'Handle');
                catch
                    error('SimulinkBlock:BlockNotFound', 'ブロックが見つかりません: %s', blockPath);
                end
            elseif ishandle(blockPath)
                % ハンドルから情報を取得
                obj.handle_ = blockPath;
                try
                    obj.fullName_ = getfullname(blockPath);
                catch
                    error('SimulinkBlock:InvalidHandle', '無効なブロックハンドル');
                end
            else
                error('SimulinkBlock:InvalidInput', '文字列またはハンドルが必要です');
            end
            
            obj.initializeBlockInfo();
        end
        
        function initializeBlockInfo(obj)
            % ブロック情報を初期化
            
            try
                % 基本情報を取得
                obj.name_ = get_param(obj.handle_, 'Name');
                obj.position_ = get_param(obj.handle_, 'Position');
                obj.blockType_ = get_param(obj.handle_, 'BlockType');
                
                % 向きを取得
                try
                    obj.orientation_ = get_param(obj.handle_, 'Orientation');
                catch
                    obj.orientation_ = 'right'; % デフォルト
                end
                
                % ポート情報を初期化
                obj.initializePortInfo();
                
            catch ME
                warning('SimulinkBlock:InitializationFailed', ...
                    'ブロック情報の初期化に失敗: %s', ME.message);
            end
        end
        
        function initializePortInfo(obj)
            % ポート情報を初期化
            
            try
                % 入力ポート
                inputPortHandles = get_param(obj.handle_, 'PortHandles');
                if isfield(inputPortHandles, 'Inport')
                    obj.inputPorts_ = obj.getPortPositions(inputPortHandles.Inport);
                else
                    obj.inputPorts_ = [];
                end
                
                % 出力ポート
                if isfield(inputPortHandles, 'Outport')
                    obj.outputPorts_ = obj.getPortPositions(inputPortHandles.Outport);
                else
                    obj.outputPorts_ = [];
                end
                
            catch ME
                warning('SimulinkBlock:PortInitializationFailed', ...
                    'ポート情報の初期化に失敗: %s', ME.message);
                obj.inputPorts_ = [];
                obj.outputPorts_ = [];
            end
        end
        
        function portPositions = getPortPositions(obj, portHandles)
            % ポート位置を取得
            
            portPositions = [];
            
            for i = 1:length(portHandles)
                try
                    pos = get_param(portHandles(i), 'Position');
                    portInfo = struct();
                    portInfo.handle = portHandles(i);
                    portInfo.position = pos;
                    portInfo.index = i;
                    
                    portPositions = [portPositions; portInfo];
                catch
                    % ポート位置取得に失敗した場合はスキップ
                end
            end
        end
        
        function subsystem = isSubsystem(obj)
            % サブシステムかどうかチェック
            subsystem = strcmp(obj.blockType_, 'SubSystem');
        end
        
        function linkLib = isLinkLibrary(obj)
            % リンクライブラリかどうかチェック
            linkLib = false;
            
            try
                if obj.isSubsystem()
                    linkStatus = get_param(obj.handle_, 'LinkStatus');
                    linkLib = ~strcmp(linkStatus, 'none');
                end
            catch
                % LinkStatusが取得できない場合はfalse
            end
        end
        
        function masked = isMasked(obj)
            % マスクされたブロックかどうかチェック
            masked = false;
            
            try
                maskType = get_param(obj.handle_, 'MaskType');
                masked = ~isempty(maskType);
            catch
                % MaskTypeが取得できない場合はfalse
            end
        end
        
        function centerPos = getCenter(obj)
            % ブロックの中心位置を取得
            pos = obj.position_;
            centerPos = [(pos(1) + pos(3))/2, (pos(2) + pos(4))/2];
        end
        
        function w = getWidth(obj)
            % ブロックの幅を取得
            pos = obj.position_;
            w = pos(3) - pos(1);
        end
        
        function h = getHeight(obj)
            % ブロックの高さを取得
            pos = obj.position_;
            h = pos(4) - pos(2);
        end
        
        function success = setPosition(obj, newPosition)
            % ブロック位置を設定
            %
            % 入力:
            %   newPosition - 新しい位置 [left top right bottom]
            
            success = false;
            
            try
                validateattributes(newPosition, {'numeric'}, {'vector', 'numel', 4});
                
                set_param(obj.handle_, 'Position', newPosition);
                obj.position_ = newPosition;
                
                % ポート情報を更新
                obj.initializePortInfo();
                
                success = true;
                
            catch ME
                warning('SimulinkBlock:SetPositionFailed', ...
                    'ブロック位置の設定に失敗: %s', ME.message);
            end
        end
        
        function success = moveBy(obj, deltaX, deltaY)
            % ブロックを相対移動
            %
            % 入力:
            %   deltaX - X方向の移動量
            %   deltaY - Y方向の移動量
            
            currentPos = obj.position_;
            newPos = currentPos + [deltaX, deltaY, deltaX, deltaY];
            success = obj.setPosition(newPos);
        end
        
        function success = moveTo(obj, x, y)
            % ブロックを指定位置に移動（左上角基準）
            %
            % 入力:
            %   x - 新しいX座標
            %   y - 新しいY座標
            
            currentPos = obj.position_;
            width = currentPos(3) - currentPos(1);
            height = currentPos(4) - currentPos(2);
            
            newPos = [x, y, x + width, y + height];
            success = obj.setPosition(newPos);
        end
        
        function success = centerAt(obj, x, y)
            % ブロックの中心を指定位置に移動
            %
            % 入力:
            %   x - 新しい中心X座標
            %   y - 新しい中心Y座標
            
            width = obj.getWidth();
            height = obj.getHeight();
            
            left = x - width/2;
            top = y - height/2;
            
            success = obj.moveTo(left, top);
        end
        
        function distance = distanceTo(obj, otherBlock)
            % 他のブロックとの距離を計算
            %
            % 入力:
            %   otherBlock - 他のSimulinkBlockオブジェクト
            
            if ~isa(otherBlock, 'SimulinkBlock')
                error('SimulinkBlock:InvalidInput', 'SimulinkBlockオブジェクトが必要です');
            end
            
            center1 = obj.getCenter();
            center2 = otherBlock.getCenter();
            
            distance = norm(center2 - center1);
        end
        
        function overlapping = isOverlapping(obj, otherBlock, margin)
            % 他のブロックと重なっているかチェック
            %
            % 入力:
            %   otherBlock - 他のSimulinkBlockオブジェクト
            %   margin - マージン（オプション、デフォルト: 0）
            
            if nargin < 3
                margin = 0;
            end
            
            if ~isa(otherBlock, 'SimulinkBlock')
                error('SimulinkBlock:InvalidInput', 'SimulinkBlockオブジェクトが必要です');
            end
            
            pos1 = obj.position_;
            pos2 = otherBlock.position_;
            
            % マージンを適用
            pos1_expanded = pos1 + [-margin, -margin, margin, margin];
            
            % 重なりチェック
            overlapping = ~(pos1_expanded(3) < pos2(1) || pos2(3) < pos1_expanded(1) || ...
                           pos1_expanded(4) < pos2(2) || pos2(4) < pos1_expanded(2));
        end
        
        function info = getBlockInfo(obj)
            % ブロック情報を構造体として取得
            
            info = struct();
            info.handle = obj.handle_;
            info.name = obj.name_;
            info.fullName = obj.fullName_;
            info.position = obj.position_;
            info.blockType = obj.blockType_;
            info.orientation = obj.orientation_;
            info.center = obj.getCenter();
            info.width = obj.getWidth();
            info.height = obj.getHeight();
            info.isSubsystem = obj.isSubsystem();
            info.isLinkLibrary = obj.isLinkLibrary();
            info.isMasked = obj.isMasked();
            info.inputPortCount = length(obj.inputPorts_);
            info.outputPortCount = length(obj.outputPorts_);
        end
    end
    
    % Dependent properties のgetter
    methods
        function value = get.handle(obj)
            value = obj.handle_;
        end
        
        function value = get.name(obj)
            value = obj.name_;
        end
        
        function value = get.fullName(obj)
            value = obj.fullName_;
        end
        
        function value = get.position(obj)
            value = obj.position_;
        end
        
        function value = get.blockType(obj)
            value = obj.blockType_;
        end
        
        function value = get.orientation(obj)
            value = obj.orientation_;
        end
        
        function value = get.inputPorts(obj)
            value = obj.inputPorts_;
        end
        
        function value = get.outputPorts(obj)
            value = obj.outputPorts_;
        end
        
        function value = get.center(obj)
            value = obj.getCenter();
        end
        
        function value = get.width(obj)
            value = obj.getWidth();
        end
        
        function value = get.height(obj)
            value = obj.getHeight();
        end
    end
end

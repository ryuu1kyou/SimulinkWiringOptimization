classdef SimulinkLine < handle
    % SIMULINKLINE Simulink信号線を表現するクラス
    %
    % このクラスは、Simulink信号線のハンドルをラップし、
    % 配線最適化に必要な操作を提供します。
    
    properties (Access = private)
        handle_         % Simulink線ハンドル
        originalPoints_ % 元の点座標
        sourceBlock_    % 送信元ブロック
        destBlock_      % 送信先ブロック
        lineType_       % 線の種類
    end
    
    properties (Dependent)
        handle
        points
        sourceBlock
        destinationBlock
        lineType
    end
    
    methods
        function obj = SimulinkLine(lineHandle)
            % コンストラクタ
            %
            % 入力:
            %   lineHandle - Simulink線のハンドル
            
            if nargin < 1 || ~ishandle(lineHandle)
                error('SimulinkLine:InvalidHandle', '有効な線ハンドルが必要です');
            end
            
            obj.handle_ = lineHandle;
            obj.initializeLineInfo();
        end
        
        function initializeLineInfo(obj)
            % 線の情報を初期化
            
            try
                % 点座標を取得
                obj.originalPoints_ = get_param(obj.handle_, 'Points');
                
                % 送信元と送信先の情報を取得
                srcPortHandle = get_param(obj.handle_, 'SrcPortHandle');
                dstPortHandle = get_param(obj.handle_, 'DstPortHandle');
                
                if srcPortHandle ~= -1
                    obj.sourceBlock_ = get_param(get_param(srcPortHandle, 'Parent'), 'Name');
                else
                    obj.sourceBlock_ = '';
                end
                
                if dstPortHandle ~= -1
                    obj.destBlock_ = get_param(get_param(dstPortHandle, 'Parent'), 'Name');
                else
                    obj.destBlock_ = '';
                end
                
                % 線の種類を判定
                obj.lineType_ = obj.determineLineType();
                
            catch ME
                warning('SimulinkLine:InitializationFailed', ...
                    '線情報の初期化に失敗: %s', ME.message);
                obj.originalPoints_ = [];
                obj.sourceBlock_ = '';
                obj.destBlock_ = '';
                obj.lineType_ = 'unknown';
            end
        end
        
        function lineType = determineLineType(obj)
            % 線の種類を判定
            
            points = obj.originalPoints_;
            if size(points, 1) < 2
                lineType = 'invalid';
                return;
            end
            
            % 直線かどうかチェック
            if size(points, 1) == 2
                if obj.isHorizontalSegment(points(1,:), points(2,:))
                    lineType = 'horizontal';
                elseif obj.isVerticalSegment(points(1,:), points(2,:))
                    lineType = 'vertical';
                else
                    lineType = 'diagonal';
                end
            else
                lineType = 'complex';
            end
        end
        
        function success = straighten(obj, method)
            % 線を直線化
            %
            % 入力:
            %   method - 直線化の方法 ('horizontal', 'vertical', 'auto')
            
            if nargin < 2
                method = 'auto';
            end
            
            success = false;
            
            try
                currentPoints = obj.getPoints();
                if size(currentPoints, 1) < 2
                    return;
                end
                
                straightenedPoints = obj.straightenPoints(currentPoints, method);
                
                if ~isequal(currentPoints, straightenedPoints)
                    obj.setPoints(straightenedPoints);
                    success = true;
                end
                
            catch ME
                warning('SimulinkLine:StraightenFailed', ...
                    '直線化に失敗: %s', ME.message);
            end
        end
        
        function straightenedPoints = straightenPoints(obj, points, method)
            % 点を直線化
            
            if size(points, 1) < 2
                straightenedPoints = points;
                return;
            end
            
            startPoint = points(1, :);
            endPoint = points(end, :);
            
            switch lower(method)
                case 'horizontal'
                    % 水平線を優先
                    midY = startPoint(2);
                    straightenedPoints = [startPoint; endPoint(1), midY; endPoint];
                    
                case 'vertical'
                    % 垂直線を優先
                    midX = startPoint(1);
                    straightenedPoints = [startPoint; midX, endPoint(2); endPoint];
                    
                case 'auto'
                    % 自動判定
                    deltaX = abs(startPoint(1) - endPoint(1));
                    deltaY = abs(startPoint(2) - endPoint(2));
                    
                    if deltaX > deltaY
                        % 水平方向が主
                        midY = startPoint(2);
                        straightenedPoints = [startPoint; endPoint(1), midY; endPoint];
                    else
                        % 垂直方向が主
                        midX = startPoint(1);
                        straightenedPoints = [startPoint; midX, endPoint(2); endPoint];
                    end
                    
                otherwise
                    straightenedPoints = points;
            end
            
            % 同じ点を除去
            straightenedPoints = obj.removeDuplicatePoints(straightenedPoints);
        end
        
        function success = removeRedundantPoints(obj)
            % 冗長な点を除去
            
            success = false;
            
            try
                currentPoints = obj.getPoints();
                cleanedPoints = obj.cleanRedundantPoints(currentPoints);
                
                if ~isequal(currentPoints, cleanedPoints)
                    obj.setPoints(cleanedPoints);
                    success = true;
                end
                
            catch ME
                warning('SimulinkLine:CleanupFailed', ...
                    '点の整理に失敗: %s', ME.message);
            end
        end
        
        function cleanedPoints = cleanRedundantPoints(obj, points)
            % 冗長な点を除去する内部メソッド
            
            if size(points, 1) <= 2
                cleanedPoints = points;
                return;
            end
            
            tolerance = 1e-6;
            cleanedPoints = points(1, :); % 開始点
            
            for i = 2:size(points, 1)-1
                prevPoint = cleanedPoints(end, :);
                currentPoint = points(i, :);
                nextPoint = points(i+1, :);
                
                % 3点が一直線上にない場合のみ追加
                if ~obj.arePointsCollinear(prevPoint, currentPoint, nextPoint, tolerance)
                    cleanedPoints = [cleanedPoints; currentPoint];
                end
            end
            
            cleanedPoints = [cleanedPoints; points(end, :)]; % 終了点
        end
        
        function collinear = arePointsCollinear(obj, p1, p2, p3, tolerance)
            % 3点が一直線上にあるかチェック
            
            if nargin < 5
                tolerance = 1e-6;
            end
            
            % ベクトルの外積を計算
            v1 = p2 - p1;
            v2 = p3 - p1;
            crossProduct = v1(1) * v2(2) - v1(2) * v2(1);
            
            collinear = abs(crossProduct) < tolerance;
        end
        
        function cleanedPoints = removeDuplicatePoints(obj, points)
            % 重複する点を除去
            
            if size(points, 1) <= 1
                cleanedPoints = points;
                return;
            end
            
            tolerance = 1e-6;
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
        
        function horizontal = isHorizontal(obj)
            % 線が水平かどうかチェック
            points = obj.getPoints();
            horizontal = obj.isHorizontalSegment(points(1,:), points(end,:));
        end
        
        function vertical = isVertical(obj)
            % 線が垂直かどうかチェック
            points = obj.getPoints();
            vertical = obj.isVerticalSegment(points(1,:), points(end,:));
        end
        
        function horizontal = isHorizontalSegment(obj, p1, p2)
            % セグメントが水平かどうかチェック
            tolerance = 1e-6;
            horizontal = abs(p1(2) - p2(2)) < tolerance;
        end
        
        function vertical = isVerticalSegment(obj, p1, p2)
            % セグメントが垂直かどうかチェック
            tolerance = 1e-6;
            vertical = abs(p1(1) - p2(1)) < tolerance;
        end
        
        function length = getLength(obj)
            % 線の総長を計算
            points = obj.getPoints();
            length = 0;
            
            for i = 1:size(points, 1)-1
                segment_length = norm(points(i+1, :) - points(i, :));
                length = length + segment_length;
            end
        end
        
        function segments = getSegmentCount(obj)
            % セグメント数を取得
            points = obj.getPoints();
            segments = max(0, size(points, 1) - 1);
        end
    end
    
    % Dependent properties のgetter/setter
    methods
        function value = get.handle(obj)
            value = obj.handle_;
        end
        
        function value = get.points(obj)
            try
                value = get_param(obj.handle_, 'Points');
            catch
                value = obj.originalPoints_;
            end
        end
        
        function setPoints(obj, newPoints)
            % 新しい点座標を設定
            try
                set_param(obj.handle_, 'Points', newPoints);
            catch ME
                warning('SimulinkLine:SetPointsFailed', ...
                    '点の設定に失敗: %s', ME.message);
            end
        end
        
        function points = getPoints(obj)
            % 現在の点座標を取得
            points = obj.points;
        end
        
        function value = get.sourceBlock(obj)
            value = obj.sourceBlock_;
        end
        
        function value = get.destinationBlock(obj)
            value = obj.destBlock_;
        end
        
        function value = get.lineType(obj)
            value = obj.lineType_;
        end
    end
end

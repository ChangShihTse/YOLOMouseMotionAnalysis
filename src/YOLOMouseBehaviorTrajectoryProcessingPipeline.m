%% ========================================================================
%% YOLO Mouse Behavior Trajectory Processing Pipeline
%% Author: Your Name / Lab Name
%% GitHub: github.com/username/repository
%% ========================================================================

clc; clear; close all;

%% 1. CONFIGURATION (配置設定區)
% 請在此處設定您的輸入/輸出資料夾與演算法參數

% --- Paths Setting (路徑設定，建議使用相對路徑以利跨平台執行) ---
dataRoot = './data/sample_labels'; % 範例輸入資料夾根目錄
outputFolder = './results/processed_data'; % 轉出 Excel 的目標資料夾

% 自動偵測或手動列出子資料夾 (取代原本寫死的 I:\... 絕對路徑)
folderPathList = {
    fullfile(dataRoot, 'exp28_MBWconf0.55M35116', 'labels');
    fullfile(dataRoot, 'exp28_MBWconf0.55M40116', 'labels');
    % 可依需求在此自由延伸
};

% --- Signal & Video Parameters (視訊與信號參數) ---
framePerSec = 23.88;       % Video FPS                    
widthofpic  = 640;         % Image Width (pixels)
lengthofpic = 352;         % Image Height (pixels)

% --- File Parsing Parameters (檔名解析參數) ---
% bg_num: 檔名中 Frame 編號開始的索引值 (例如 'Sle_...' 填 16, 'Awa_...' 填 30)
bg_num = 16;               
outputSuffix = 'Sle_1217_MBWV11s'; % 輸出 Excel 檔名的辨識尾綴

% --- Algorithm Thresholds (演算法門檻值) ---
confThreshold  = 0.55;     % YOLO Bounding Box 信心度門檻
CheckFreq      = 1;        % 軌跡位移統計的時間間隔 (秒)
timeWindow_len = 1;        % 滑動視窗長度 (秒)

% --- Spatial Boundary Constraints (行為箱空間邊界結構體) ---
boundParams.widthLeft   = 110;
boundParams.widthRight  = 492;
boundParams.lengthLeft  = 98;
boundParams.lengthRight = 304;

% --- Legacy/Reserved Parameters (保留參數) ---
totalmoving_dis_thres = 47.882;
sleepLabel = 0; awakeLabel = 1;

%% 2. INITIALIZATION & PRE-CHECK
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

%% 3. MAIN EXECUTION LOOP (主核心循環)
for k = 1:length(folderPathList)
    folderPath = folderPathList{k};
    if ~exist(folderPath, 'dir')
        fprintf('警告: 找不到路徑 %s，跳過此資料夾。\n', folderPath);
        continue;
    end
    fprintf('正在處理 (%d/%d): %s\n', k, length(folderPathList), folderPath);
    
    % --- Dynamic Output Filename Generation ---
    parentPath = fileparts(folderPath); 
    [~, name, ext] = fileparts(parentPath);
    fileID = [name, ext]; 
    currentOutputFileName = sprintf('%s_%s.xlsx', fileID, outputSuffix);      
    outputFile = fullfile(outputFolder, currentOutputFileName);
    
    % --- Load and Sort TXT Files ---
    txtFiles = dir(fullfile(folderPath, '*.txt'));
    numFiles = length(txtFiles);
    if numFiles == 0
        fprintf('提示: 資料夾內無 txt 檔案。\n'); continue;
    end
    
    fileNumbers = zeros(1, numFiles);
    for i = 1:numFiles
        try 
            fileNumbers(i) = str2double(txtFiles(i).name(bg_num:end-4));
        catch
            error('檔名解析失敗，請確認 bg_num 與當前檔名結構是否匹配。');
        end
    end
    [~, sortIdx] = sort(fileNumbers);
    sortedFiles = txtFiles(sortIdx);
    
    %% [邏輯骨架] 初始化首幀、補零對齊、計算歐式距離與時間窗統計
    %排序所有txt檔案
    for i = 1:numFiles
        try 
            fileNumbers(i) = str2double(txtFiles(i).name(bg_num:end-4));
        catch
            error('檔名解析失敗，請確認 bg_num 設定');
        end
    end
    [~, sortIdx] = sort(fileNumbers);
    sortedFiles = txtFiles(sortIdx);

    %計算總共有幾張超出範圍的frame幾張合法的frame
    mouseDetectedFrames = 0;
    missingFrames = 0;
    i = 1;
    
    % Initialize counters: 尋找第一張符合所有條件的禎
    while true
        if i > numFiles
            warning('No valid initial frame found in folder %s. Skipping.', folderPath);
            break; 
        end
        currentFile = fullfile(folderPath, sortedFiles(i).name);
        try
            firstData = readtable(currentFile, 'Delimiter', ' ', 'ReadVariableNames', false);
        catch
             i = i + 1;
             missingFrames = missingFrames + 1;
             continue;
        end
        
        % 條件 1: 檔案必須有內容
        if isempty(firstData)
            missingFrames = missingFrames + 1;
            i = i + 1;
            continue;
        end

        [bestConf, firstBestIdx] = max(firstData.Var6);
        currentX = firstData.Var2(firstBestIdx) * widthofpic;
        currentY = firstData.Var3(firstBestIdx) * lengthofpic;
        
        % 條件 2 & 3: 檢查 邊界(Bounds) 與 信心度(Confidence)
        isSpatialValid = checkLabelValidity(currentX, currentY, boundParams);
        isConfValid = bestConf > confThreshold;
        
        % 只要有一個不符合，就算 OutOfBounds
        if ~isSpatialValid || ~isConfValid
            missingFrames = missingFrames + 1;
            i = i + 1;
            continue;
        else
            % 三個條件同時成立
            prevX = currentX;
            prevY = currentY;
            mouseDetectedFrames = mouseDetectedFrames + 1;
            break;
        end
    end
    
    if i > numFiles
        continue;
    end

    % 設定參數
    prevFileNum = str2double(sortedFiles(1).name(bg_num:end-4));
    maxFrameNum = str2double(sortedFiles(end).name(bg_num:end-4));
    allFrameNums = prevFileNum:maxFrameNum;
    maxRecords = length(allFrameNums);
    distanceRecords = zeros(1, maxRecords);   
    timeStamps = zeros(1, maxRecords);   
    timeStamps(1) = prevFileNum / framePerSec;
    
    recordIdx = 1;
    
    %% 計算每一點距離並放到distanceRecords
    fileIdx = i + 1;
    
    for frameNum = allFrameNums(2:end)
        isMatch = false;
        if fileIdx <= numFiles
            currentFileNameNum = str2double(sortedFiles(fileIdx).name(bg_num:end-4));
            if currentFileNameNum == frameNum
                isMatch = true;
            end
        end

        if isMatch
            currentFile = fullfile(folderPath, sortedFiles(fileIdx).name);
            currentData = readtable(currentFile, 'Delimiter', ' ', 'ReadVariableNames', false);
            
            % 條件 1: 檔案有內容
            if ~isempty(currentData)
                [bestConf, bestIdx] = max(currentData.Var6);       
                currentX = currentData.Var2(bestIdx) * widthofpic;
                currentY = currentData.Var3(bestIdx) * lengthofpic;
                
                % 條件 2 & 3: 檢查 邊界(Bounds) 與 信心度(Confidence)
                isSpatialValid = checkLabelValidity(currentX, currentY, boundParams);
                isConfValid = bestConf > confThreshold;

                % 嚴格判定：任一條件不符即視為無效
                if ~isSpatialValid || ~isConfValid
                    distanceRecords(recordIdx) = 0;
                    missingFrames = missingFrames + 1;
                else
                    % --- 全部符合 (1&2&3) ---
                    distanceRecords(recordIdx) = calculateEuclideanDist(prevX, prevY, currentX, currentY);
                    
                    prevX = currentX;
                    prevY = currentY;
                    mouseDetectedFrames = mouseDetectedFrames + 1; 
                end
            else
                % 檔案是空的 (Empty)
                distanceRecords(recordIdx) = 0;
                missingFrames = missingFrames + 1;
            end
            
            prevFileNum = frameNum;
            fileIdx = fileIdx + 1;
        else
            % 檔案不存在 (Missing Frame)
            distanceRecords(recordIdx) = 0; 
            missingFrames = missingFrames + 1;
        end
        timeStamps(recordIdx + 1) = frameNum / framePerSec;
        recordIdx = recordIdx + 1;
    end
    
    %% 計算CheckFreq內秒數的距離並記錄
    lastUpdateTime = timeStamps(1);
    
    % 重新抓取第一筆有效資料做初始化 (用於計算時間，座標已不需要重算)
    % 注意：這裡不需要再做邏輯判斷，因為 i 已經停在第一個合法的點了
    prevFileNum = str2double(sortedFiles(1).name(bg_num:end-4));
    
    results2 = {};
    for j = 2:length(timeStamps) 
        currentTime = timeStamps(j);
        currentFileNum = allFrameNums(j);
        if (currentTime - lastUpdateTime) >= CheckFreq
            timeWindowStart = currentTime - timeWindow_len;
            validIdx = timeStamps(1:end-1) >= timeWindowStart & timeStamps(1:end-1) <= currentTime;
            totalDistance = sum(distanceRecords(validIdx));
            prevTime = round(prevFileNum / framePerSec, 2);
            diffTime = round(currentTime - prevTime, 2);
            prevTimeStr = sprintf('%02d:%02d:%02d.%02d', floor(prevTime / 3600), floor(mod(prevTime, 3600) / 60), floor(mod(prevTime, 60)), round(mod(prevTime, 1) * 100));
            currTimeStr = sprintf('%02d:%02d:%02d.%02d', floor(currentTime / 3600), floor(mod(currentTime, 3600) / 60), floor(mod(currentTime, 60)), round(mod(currentTime, 1) * 100));
            results2(end + 1, :) = {prevTimeStr, currTimeStr, diffTime, prevFileNum, currentFileNum, totalDistance};
            prevFileNum = currentFileNum;
            lastUpdateTime = currentTime;
        end
    end
    
    %% 處理最後一筆資料
    timeWindowStart = lastUpdateTime;
    validIdx = find(timeStamps(1:end-1) >= timeWindowStart);
    totalDistance = sum(distanceRecords(validIdx));
    finalTime = round(prevFileNum / framePerSec, 2);
    EndTime = round(currentFileNum / framePerSec, 2);
    finalTimeStr = sprintf('%02d:%02d:%02d.%02d', floor(finalTime / 3600), floor(mod(finalTime, 3600) / 60), floor(mod(finalTime, 60)), round(mod(finalTime, 1) * 100));
    EndTimeStr = sprintf('%02d:%02d:%02d.%02d', floor(EndTime / 3600), floor(mod(EndTime, 3600) / 60), floor(mod(EndTime, 60)), round(mod(EndTime, 1) * 100));
    diffTime = round((currentFileNum - prevFileNum) / framePerSec, 2);
    results2(end + 1, :) = {finalTimeStr, EndTimeStr, diffTime, prevFileNum, currentFileNum, totalDistance};
    
    fprintf(' -> distanceRecords 計算完成，準備寫入 Excel...\n');
    
    %% --- Data Export (資料封裝輸出) ---
    % 資料輸出到 xlsx
    resultTable = cell2table(results2, 'VariableNames', {'Prev_Time', 'Curr_Time', 'Time_Diff', 'Prev_Value', 'Curr_Value','Total_Distance_fornext3sec'});
    
    writetable(resultTable, outputFile);
    
    params = {'CheckFrequence', CheckFreq; 'FramePerSec', framePerSec; ...
        'TimeWindow_len', timeWindow_len; 'Sleep lebel', sleepLabel; 'Awake lebel', awakeLabel; ...
        'Moving_Dis_Threshold(pixel)', totalmoving_dis_thres;...
        'Confidence_Threshold', confThreshold; ... % 紀錄一下信心門檻
        'mouseDetectedFrames', mouseDetectedFrames; 'missingFrames', missingFrames;...
        'maxFrameNum', maxFrameNum; 'DetectedFramesRate(max/mouse)', round(mouseDetectedFrames / maxFrameNum, 2)};
    paramTable = cell2table(params, 'VariableNames', {'Parameter', 'Value'});
    
    writetable(paramTable, outputFile, 'Sheet', 2);
    
    fprintf(' -> 資料已匯出至: %s (Sheet1 & Sheet2)\n', outputFile);
    fprintf('------------------------------------------------------\n');
end
fprintf('所有資料夾處理完畢！\n');

%% ========================================================================
%% LOCAL FUNCTIONS (在地函數區)
%% ========================================================================
function isValid = checkLabelValidity(x, y, bounds)
    % 檢查座標是否落在定義的實驗箱邊界內
    isValid = (x >= bounds.widthLeft && x <= bounds.widthRight && ...
               y >= bounds.lengthLeft && y <= bounds.lengthRight);
end

function dist = calculateEuclideanDist(x1, y1, x2, y2)
    % 計算相鄰兩訊號點間的歐式距離
    dist = sqrt((x2 - x1)^2 + (y2 - y1)^2);
end
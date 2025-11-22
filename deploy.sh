#!/bin/bash

# --- 專案配置 ---
CONTAINER_NAME="ais2api"
# [重要] 請確保此處名稱與您本地 build 的名稱一致
# 例如您使用 'docker build -t ais2api:local .'，這裡就填 'ais2api:local'
IMAGE_NAME="ais2api" 
HOST_PORT="8899"
ENV_FILE="app.env" # 指定您的環境變數檔名

# --- 代理配置 ---
PROXY_URL=""

# -------------------------------------------------------------------

# 檢查環境變數檔案是否存在
if [ ! -f "$ENV_FILE" ]; then
    echo "錯誤: 環境變數檔案 '$ENV_FILE' 不存在！"
    exit 1
fi

echo "===== 開始部署: $CONTAINER_NAME (本地模式) ====="

# 1. 檢查本地 Image 是否存在 (取代原本的拉取步驟)
echo "--> 正在檢查本地 Image: $IMAGE_NAME..."
if [[ "$(docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then
    echo "錯誤: 找不到本地 Image '$IMAGE_NAME'"
    echo "請確認您是否已經執行 build，且名稱與腳本中的 IMAGE_NAME 一致。"
    exit 1
else
    echo "--> 檢測到本地 Image，準備使用。"
fi

# 2. 停止並刪除同名的舊容器
echo "--> 正在停止並刪除舊容器..."
docker stop $CONTAINER_NAME > /dev/null 2>&1
docker rm $CONTAINER_NAME > /dev/null 2>&1

# 3. 準備並執行新容器
echo "--> 正在啟動新容器..."

# 使用陣列來構建 docker run 命令的參數
declare -a DOCKER_OPTS
DOCKER_OPTS=(
    -d
    --name "$CONTAINER_NAME"
    -p "${HOST_PORT}:7860"
    --env-file "$ENV_FILE"
    --restart unless-stopped
)

# 條件性地向陣列中添加掛載參數
if [ -d "./auth" ]; then
    echo "--> 檢測到 'auth' 目錄..."
    
    # [核心修正] 在掛載前，自動修正目錄權限
    echo "--> 正在為 'auth' 目錄設定權限..."
    sudo chown -R 1000:1000 ./auth
    
    echo "--> 正在將 'auth' 目錄掛載到容器中..."
    DOCKER_OPTS+=(-v "$(pwd)/auth:/app/auth")
else
    echo "--> 未檢測到 'auth' 目錄，跳過掛載。"
fi

# 條件性地向陣列中添加代理參數
if [ -n "$PROXY_URL" ]; then
    echo "--> 檢測到代理配置，將為容器啟用代理: $PROXY_URL"
    DOCKER_OPTS+=(-e "HTTP_PROXY=${PROXY_URL}")
    DOCKER_OPTS+=(-e "HTTPS_PROXY=${PROXY_URL}")
else
    echo "--> 未配置代理。"
fi

# 使用陣列展開來執行命令，確保參數正確傳遞
docker run "${DOCKER_OPTS[@]}" "$IMAGE_NAME"


# 4. 檢查容器狀態
echo ""
echo "--> 檢查容器狀態 (等待幾秒鐘讓容器啟動):"
sleep 5
docker ps | grep $CONTAINER_NAME

echo ""
echo "===== 部署完成！====="
echo "服務應該正在運行在 http://<您的伺服器IP>:${HOST_PORT}"
echo "您可以用 'docker logs -f $CONTAINER_NAME' 查看即時日誌。"

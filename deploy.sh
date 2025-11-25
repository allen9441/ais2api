#!/bin/bash

# --- 專案配置 ---
CONTAINER_NAME="ais2api"

IMAGE_NAME="ghcr.io/allen9441/ais2api:latest" 
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

echo "===== 開始部署: $CONTAINER_NAME ====="
echo "目標 Image: $IMAGE_NAME"
# 1. 拉取最新的 Image
echo "--> 正在從 GitHub Container Registry 拉取最新 Image..."
if docker pull "$IMAGE_NAME"; then
    echo "--> 拉取成功。"
else
    echo "-----------------------------------------------------"
    echo "錯誤: 拉取 Image 失敗！"
    echo "可能原因："
    echo "1. Image 名稱錯誤 (大小寫敏感，GHCR 通常要求全小寫)。"
    echo "2. 若這是私有庫 (Private Repo)，請先執行: echo \$CR_PAT | docker login ghcr.io -u <username> --password-stdin"
    echo "-----------------------------------------------------"
    exit 1
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
    
    # [重要] 修正權限：因為 Dockerfile 使用 USER node (UID 1000)
    # 宿主機的資料夾必須允許 UID 1000 讀寫
    echo "--> 正在為 'auth' 目錄設定權限 (chown 1000:1000)..."
    if sudo -n true 2>/dev/null; then
        sudo chown -R 1000:1000 ./auth
    else
        echo "警告: 無法使用 sudo 自動修正權限，請確保 ./auth 目錄權限為 1000:1000 (node)"
    fi
    
    echo "--> 正在將 'auth' 目錄掛載到容器中..."
    DOCKER_OPTS+=(-v "$(pwd)/auth:/app/auth")
else
    echo "--> 未檢測到 'auth' 目錄，建議建立此目錄以持久化登入資訊。"
    echo "    (執行: mkdir auth && sudo chown 1000:1000 auth)"
fi
# 條件性地向陣列中添加代理參數
if [ -n "$PROXY_URL" ]; then
    echo "--> 檢測到代理配置，將為容器啟用代理: $PROXY_URL"
    DOCKER_OPTS+=(-e "HTTP_PROXY=${PROXY_URL}")
    DOCKER_OPTS+=(-e "HTTPS_PROXY=${PROXY_URL}")
else
    echo "--> 未配置代理。"
fi
# 執行 Docker 命令
echo "--> 執行命令中..."
docker run "${DOCKER_OPTS[@]}" "$IMAGE_NAME"
# 4. 檢查容器狀態
echo ""
echo "--> 檢查容器狀態 (等待 5 秒讓容器啟動):"
sleep 5
# 檢查容器是否仍在運行
if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" = "true" ]; then
    echo "✅ 部署成功！"
    echo "服務位置: http://$(curl -s ifconfig.me):${HOST_PORT} (或伺服器內網 IP)"
    echo "查看日誌: docker logs -f $CONTAINER_NAME"
else
    echo "❌ 部署可能失敗，容器已停止。"
    echo "請檢查日誌: docker logs $CONTAINER_NAME"
fi

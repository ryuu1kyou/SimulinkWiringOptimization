import sys
import os
import json
import requests
import base64
import re

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")

def evaluate_image(image_path, before_image_path=None):
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("NO_API_KEY: OPENAI_API_KEY environment variable not set. Switching to manual evaluation.")
        return -1  # 特別な戻り値で手動評価モードに切り替えることを示す

    # Prepare the prompt based on whether we have one or two images
    if before_image_path:
        prompt = "これらはSimulinkモデルの配線図の最適化前後の画像です。以下の配線最適化の原則とルールに基づいて改善点を評価し、"
        prompt += "さらなる改善のための提案をしてください。\n\n"
    else:
        prompt = "この画像はSimulinkモデルの配線図です。以下の配線最適化の原則とルールに基づいて配線の品質を評価してください。\n\n"

    # Add common evaluation criteria
    prompt += "【配線最適化の原則】\n"
    prompt += "1. できるだけ直線的な配線を維持する（垂直・水平の線を優先）\n"
    prompt += "2. 配線の交差を最小限に抑える\n"
    prompt += "3. 近接した配線は上下左右に適切に分散させる\n"
    prompt += "4. 全体的に美しく整理されたレイアウトを実現する\n"
    prompt += "5. サブシステムごとに少しずつ調整する（一度にモデル全体を調整しない）\n\n"

    prompt += "【重要なルール】\n"
    prompt += "- 既存の線を削除せずに配線を整理する\n"
    prompt += "- 近接した線は上下左右に移動して重なりを避ける\n"
    prompt += "- 各線の垂直・水平の整列を維持しながら、視覚的な明瞭さを向上させる\n"
    prompt += "- 元の接続は絶対に変更しない（始点と終点は保持）\n"
    prompt += "- 配線の交差を最小限に抑え、全体的に美しいレイアウトを実現する\n"
    prompt += "- サブシステムごとに個別に処理し、階層の異なるサブシステム間のバランスを考慮する\n"
    prompt += "- サブシステム入力ポートの配線は垂直に揃えず、適切に間隔を空ける\n\n"

    if before_image_path:
        prompt += "最適化の改善度を0〜100の範囲でスコア付けしてください。"
    else:
        prompt += "0〜100の範囲でスコアを付けてください。"

    # Prepare the API request
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }

    # Prepare the message content for OpenAI
    messages = [
        {"role": "user", "content": []}
    ]

    # Add text prompt
    messages[0]["content"].append({
        "type": "text",
        "text": prompt
    })

    # Add the image(s) to the message
    image_data = encode_image(image_path)
    messages[0]["content"].append({
        "type": "image_url",
        "image_url": {"url": f"data:image/png;base64,{image_data}"}
    })

    if before_image_path:
        before_image_data = encode_image(before_image_path)
        messages[0]["content"].append({
            "type": "image_url",
            "image_url": {"url": f"data:image/png;base64,{before_image_data}"}
        })

    # Make the API request to OpenAI
    try:
        response = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers=headers,
            json={
                "model": "gpt-4o",  # OpenAI's model with vision capabilities
                "messages": messages,
                "max_tokens": 1000
            }
        )
        response.raise_for_status()
        result = response.json()

        # Extract the score from the response
        ai_response = result["choices"][0]["message"]["content"]
        print("AI Evaluation:")
        print(ai_response)

        # Extract score using regex
        score_match = re.search(r"\b([0-9]{1,3})\s*[/／]\s*100\b|\bスコア[：:]*\s*([0-9]{1,3})\b|\b評価[：:]*\s*([0-9]{1,3})\b|\b([0-9]{1,3})\s*点\b", ai_response)
        if score_match:
            # Get the first non-None group
            for group in score_match.groups():
                if group is not None:
                    score = int(group)
                    print(f"Extracted score: {score}")
                    return score

        # If no score found, ask the AI directly
        clarification_response = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers=headers,
            json={
                "model": "gpt-4o",
                "messages": [
                    {"role": "user", "content": [{"type": "text", "text": prompt}]},
                    {"role": "assistant", "content": ai_response},
                    {"role": "user", "content": "0から100の範囲で具体的な数値スコアだけを教えてください。"}
                ],
                "max_tokens": 50
            }
        )
        clarification_response.raise_for_status()
        clarification_result = clarification_response.json()
        clarification_text = clarification_result["choices"][0]["message"]["content"]
        print("AI Clarification:")
        print(clarification_text)

        # Try to extract just the number
        score_match = re.search(r"\b([0-9]{1,3})\b", clarification_text)
        if score_match:
            score = int(score_match.group(1))
            if 0 <= score <= 100:
                print(f"Extracted score from clarification: {score}")
                return score

        print("Could not extract a valid score, using default value of 50")
        return 50

    except Exception as e:
        print(f"Error: {str(e)}")
        return 50  # Default score

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python evaluate_simulink_image.py <image_path> [<before_image_path>]")
        sys.exit(1)

    image_path = sys.argv[1]
    before_image_path = sys.argv[2] if len(sys.argv) > 2 else None

    score = evaluate_image(image_path, before_image_path)
    print(f"Final score: {score}")
    # Output the score as the last line for easy parsing
    print(f"SCORE:{score}")

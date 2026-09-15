Сюда кладём отредактированные партитуры. Рабочий цикл:

1. `bash play.sh plan prompts/x.json plan` → `outputs/plan/score.abc`
2. копия сюда, правки (аккорды в кавычках `"Am7"`, тональность `K:`, темп `Q:`)
3. `bash play.sh compare outputs/plan/score.abc edits/x.abc --voices Vocal` — проверяет, что мелодия не тронута
4. `bash play.sh generate prompts/x.json x-edited --abc-file edits/x.abc`

Подсказки по ABC: `skills/yue2-music/references/abc-editing.md` в репо YuE.

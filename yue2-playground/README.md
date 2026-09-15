# YuE2 playground

Песочница для [YuE2-3B](https://github.com/multimodal-art-projection/YuE): открытая модель, которая из текста и описания стиля делает полную песню с вокалом, но сначала пишет партитуру в ABC, которую можно править и перерендеривать. Цель проекта: погонять агентный цикл «сгенерил → послушал → сказал фидбек словами → агент поправил партитуру → перегенерил».

Веса под CC BY-NC 4.0: только личное и исследовательское использование.

## Что нужно

- RunPod (или любой Linux с NVIDIA). Официальное требование: BF16, **24 GB VRAM**.
- Аккаунт Hugging Face на всякий случай (веса публичные, но если попросит логин — `export HF_TOKEN=hf_...`).
- Claude Code на pod'е ставится скриптом; логин через `claude auth login`.

### Какой pod брать

Цены RunPod на сентябрь 2026, $/час, Secure / Community. Что важно для YuE2: это авторегрессионный трансформер на 3B плюс flow matching, упирается в пропускную способность памяти, не в FLOPS. Поэтому смотрим на bandwidth, а не на «мощность».

| GPU | VRAM | Bandwidth | Secure | Community | Вердикт |
|---|---|---|---|---|---|
| **RTX 5090** | 32 GB | 1.79 TB/s | $0.99 | $0.69 | **брать**: в ~1.5 раза быстрее 4090, 8 GB запаса над минимумом |
| RTX 4090 | 24 GB | 1.01 TB/s | $0.69 | $0.34 | самый дешёвый вариант, впритык по VRAM |
| RTX PRO 6000 | 96 GB | 1.79 TB/s | $1.99 | — | та же скорость, что 5090, платишь за память, которая не нужна |
| A100 80 GB | 80 GB | 2.0 TB/s | $1.39 | — | чуть быстрее 5090 за 1.4 цены |
| H100 PCIe | 80 GB | 2.0 TB/s | $1.99 | — | для 3B модели бессмысленно |
| L40S | 48 GB | 0.86 TB/s | $0.79 | $0.86 | медленнее 4090 и дороже |
| RTX A6000 | 48 GB | 0.77 TB/s | — | $0.49 | медленно |
| RTX 3090 | 24 GB | 0.94 TB/s | — | $0.46 | дешёвый резерв, если 4090/5090 нет в наличии |
| RTX A5000 | 24 GB | 0.77 TB/s | — | $0.27 | самый дешёвый час, самая долгая песня |
| L4 / T4 | 24 / 16 GB | 0.3 TB/s | — | — | мимо: L4 очень медленный, T4 без BF16 |

Расклад: 5090 Secure за $0.99 делает песню быстрее, чем 4090 Secure за $0.69, и в пересчёте на песню выходит дешевле. Community 4090 за $0.34 остаётся самым дешёвым часом, если готов ждать. Мы работаем интерактивно, pod крутится пока мы слушаем и правим, так что скорость ответа важнее центов за час.

Настройки в RunPod:
- **GPU:** RTX 5090. Нет в наличии в регионе → RTX 4090 → RTX 3090.
- **Cloud:** Secure для спокойной работы, Community если хочется сэкономить и не жалко потерять сессию. On-demand, **не Spot**: прерванная генерация теряется.
- **Фильтр CUDA:** 12.8 и выше. Обязательно для 5090 (Blackwell), на 4090 не мешает.
- **Шаблон:** любой RunPod PyTorch, версия не важна: свои venv ставим через uv.
- **Диск:** container 20 GB, **network volume 60 GB** вместо обычного volume. Он переживает удаление pod'а и позволяет менять GPU внутри региона, не перекачивая 13 GB весов. $0.07/GB/мес, то есть ~$4 в месяц. Монтируется в `/workspace`, скрипты этого и ждут.

## Запуск за 4 шага

```bash
# 1. на pod'е (через web-terminal или ssh)
cd /workspace
git clone https://github.com/malaeu/the-book-of-secret-knowledge.git -b claude/claude-siri-setup-sip-d0k40x book
cd book/yue2-playground

# 2. всё ставится и качается само, в конце генерит первую песню
bash setup_runpod.sh

# 3. слушать: забрать на Mac (ssh-строку даёт RunPod в карточке pod'а)
scp -P <port> -r root@<host>:/workspace/book/yue2-playground/outputs/first-song ~/Desktop/

# 4. агентный режим
claude          # в папке yue2-playground; скилл yue2-music уже в ~/.claude/skills
```

Первый запрос в Claude Code, который предлагают сами авторы:

> Use the yue2-music skill to create an English piano-pop song. Keep the original audio and score. Make a second version with jazz harmony, preserve the vocal melody and lyric order, and give me both versions to compare.

## Ручные команды

```bash
bash play.sh generate prompts/neon_garage.json first-song      # песня + партитура
bash play.sh modes    prompts/neon_garage.json modes           # full / melody / off рядом, сравнить
bash play.sh plan     prompts/neon_garage.json plan            # только ABC, без звука, быстро
bash play.sh inspect  outputs/plan/score.abc                   # что модель придумала

# правим партитуру (аккорды, тональность) и рендерим ту же мелодию заново
cp outputs/plan/score.abc edits/jazz.abc && $EDITOR edits/jazz.abc
bash play.sh compare  outputs/plan/score.abc edits/jazz.abc --voices Vocal
bash play.sh generate prompts/neon_garage.json jazz --abc-file edits/jazz.abc

# A/B страница с плеерами, самодостаточная, можно scp-нуть целиком
bash play.sh listen outputs/first-song outputs/jazz
```

Каждый запуск идёт в новую папку `outputs/<name>` и никогда не перезаписывается. Внутри: `audio.flac` (48 kHz стерео), `score.abc`, `semantic.npy`, `latent.npy`, `request.json`, `result.json`. Это нужно, чтобы любую версию можно было воспроизвести и сравнить.

## Что проверяем в первую очередь

1. Поёт ли по-русски (`prompts/moscow_rain.json`). В доках языков нет, есть только английский и китайский примеры.
2. Насколько правка аккордов в ABC реально меняет звук при той же мелодии.
3. Сколько секунд генерация на 4090 и сколько реально ест VRAM (`nvidia-smi` во второй вкладке).
4. Кавер: взять свой wav, `transcribe.py` (нужна вторая venv с SheetSage2, см. `skills/yue2-music/references/models-and-setup.md`), снять аккорды, перепеть в другом стиле.

## MP3 → партитура → кавер

Как это устроено. Слушает не Claude и не YuE2, а третья модель, **SheetSage2** (поверх энкодера MERT-v2). Она достаёт из записи мелодию, аккорды, биты, тональность и структуру и сериализует в ABC. Дальше YuE2 берёт эту мелодию как условие и **поёт её заново** с твоим стилем и твоим текстом. Голос исходного певца, аранжировка и сам звук записи не переносятся: это перепевка мелодии, не ремикс и не клон.

```bash
bash setup_cover.sh                                              # один раз: второй venv + SheetSage2 (~3 GB)

# 1. только транскрипция, посмотреть партитуру
bash play.sh transcribe song.mp3 song-score                      # outputs/song-score/score.abc + midi + lab-файлы
bash play.sh transcribe song.mp3 song-vocal --task melody-vocal  # только вокальная линия, без инструментальных соло

# 2. кавер одной командой: транскрипция + генерация с cot=melody
cp prompts/cover_template.json prompts/my_cover.json             # вписать целевой стиль и слова
bash play.sh cover song.mp3 prompts/my_cover.json my-cover
```

Что важно:
- Текст песни YuE2 не слышит. Слова ты даёшь сам в `lyrics`; хочешь оригинальные — вставь их, хочешь перевод — адаптируй слоги под мелодию. Автоматическое распознавание слов (whisper) сюда легко добавить, пока не делал.
- Транскрипция ошибается. Перед генерацией открой `score.abc` (`play.sh inspect`), посмотри `warnings` в `transcription_manifest.json`. Пропущенные ноты, неверный размер или тональность лучше поправить руками или через Claude, чем валить на YuE2.
- `--task melody-full` (по умолчанию) оставляет вокал и инструментальные мелодии без аккордов, `melody-vocal` только вокал. Если нужна ещё и оригинальная гармония, `--task full` и потом `generate --cot full`.
- Где роль Claude: он оркестрирует цепочку, читает ABC, чинит транскрипцию, правит аккорды и текст по твоему фидбеку. Именно для этого скилл yue2-music.

## Если меньше 24 GB

`play.sh` сам передаёт `--memory-budget-gib` по размеру карты. Официально это не поддерживается: может OOM-нуть на длинной песне. Тогда либо короче текст, либо карта побольше.

## Стоимость ориентировочно

5090 Secure $0.99/ч, 4090 Community $0.34/ч. Установка и скачивание весов ~15 минут, одна песня минуты. Вечер экспериментов на 5090 — $3–5. Не забудь **Stop** pod: остановленный pod с обычным volume платит $0.20/GB/мес за диск, network volume дешевле и не привязан к pod'у.

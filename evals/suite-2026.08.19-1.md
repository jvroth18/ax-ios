# Tool-calling eval suite `2026.08.19-1`

Reference "now" for every case: **Wednesday 2026-08-19 14:30, America/New_York**.

43 cases across 6 classes.

## Single tool (10)

| Case | Transcript | Expects |
| --- | --- | --- |
| `single-flashlight-on` | "Turn on the flashlight" | toggle_flashlight · toggle_flashlight.state |
| `single-flashlight-indirect` | "It's pitch black in here, can you give me some light" | toggle_flashlight · toggle_flashlight.state |
| `single-music-pause` | "Pause the music" | play_music · play_music.action |
| `single-music-next` | "Skip this song" | play_music · play_music.action |
| `single-timer-10` | "Set a timer for 10 minutes" | set_timer · set_timer.minutes |
| `single-timer-90-seconds` | "Set a timer for a minute and a half" | set_timer · set_timer.minutes |
| `single-calendar-read` | "What's on my calendar today?" | read_next_events |
| `single-open-maps` | "Open Maps" | open_app · open_app.app |
| `single-find-contact` | "What's Dave's phone number?" | find_contact · find_contact.name |
| `single-run-shortcut` | "Run my Goodnight shortcut" | run_shortcut · run_shortcut.name |

## Date extraction (12)

| Case | Transcript | Expects |
| --- | --- | --- |
| `date-reminder-5pm-today` | "Remind me to call mom at 5pm today" | create_reminder · create_reminder.due, create_reminder.title |
| `date-calendar-lunch-tomorrow-noon` | "Put lunch with Sarah on my calendar tomorrow at noon" | create_calendar_event · create_calendar_event.start, create_calendar_event.title |
| `date-reminder-tomorrow-8am` | "Remind me to take the trash out tomorrow morning at eight" | create_reminder · create_reminder.due, create_reminder.title |
| `date-reminder-tonight-9` | "Remind me to take my medicine tonight at nine" | create_reminder · create_reminder.due, create_reminder.title |
| `date-calendar-friday-9am` | "Schedule a dentist appointment for Friday at 9am" | create_calendar_event · create_calendar_event.start, create_calendar_event.title |
| `date-reminder-saturday-noon` | "Remind me to call the vet on Saturday at noon" | create_reminder · create_reminder.due, create_reminder.title |
| `date-reminder-in-20-minutes` | "Remind me in twenty minutes to check the oven" | create_reminder · create_reminder.due, create_reminder.title |
| `date-calendar-next-monday-3pm` | "Block out three o'clock next Monday for the design review" | create_calendar_event · create_calendar_event.start, create_calendar_event.title |
| `date-calendar-30-minute-call` | "Put a thirty minute call with Alex on my calendar at four today" | create_calendar_event · create_calendar_event.duration_minutes, create_calendar_event.start, create_calendar_event.title |
| `date-calendar-tomorrow-830` | "Coffee with Priya tomorrow at eight thirty in the morning" | create_calendar_event · create_calendar_event.start, create_calendar_event.title |
| `date-reminder-no-time` | "Remind me to buy milk" | create_reminder · create_reminder.due, create_reminder.title |
| `date-reminder-day-after-tomorrow` | "Remind me to send the invoice the day after tomorrow at ten in the morning" | create_reminder · create_reminder.due, create_reminder.title |

## Negative (no tool) (8)

| Case | Transcript | Expects |
| --- | --- | --- |
| `negative-capital-of-france` | "What's the capital of France?" | no tool call |
| `negative-small-talk` | "How's your day going?" | no tool call |
| `negative-thanks` | "Thanks, that's all for now" | no tool call |
| `negative-minutes-in-a-day` | "How many minutes are there in a day?" | no tool call |
| `negative-what-time-is-it` | "What time is it right now?" | no tool call |
| `negative-capability-question` | "Can you actually see my calendar?" | no tool call |
| `negative-joke` | "Tell me a joke about penguins" | no tool call |
| `negative-explain-acronym` | "What does the acronym API stand for?" | no tool call |

## Multi-step (4)

| Case | Transcript | Expects |
| --- | --- | --- |
| `multi-call-dave` | "Call Dave" | find_contact → call_number · find_contact.name, call_number.number |
| `multi-call-mom` | "Give my mom a ring" | find_contact → call_number · find_contact.name, call_number.number |
| `multi-text-sarah-late` | "Text Sarah that I'm running about ten minutes late" | find_contact → compose_message · find_contact.name, compose_message.body, compose_message.number |
| `multi-lookup-then-call` | "Find Dave's number and then call him" | find_contact → call_number · find_contact.name, call_number.number |

## Ambiguity (5)

| Case | Transcript | Expects |
| --- | --- | --- |
| `ambiguous-remind-me-about-the-thing` | "Remind me about the thing" | no tool call — a clarifying question |
| `ambiguous-set-a-timer` | "Set a timer" | no tool call — a clarifying question |
| `ambiguous-put-it-on-my-calendar` | "Put it on my calendar" | no tool call — a clarifying question |
| `ambiguous-open-it` | "Open it" | no tool call — a clarifying question |
| `ambiguous-text-her` | "Text her that I'll be there" | no tool call — a clarifying question |

## Spurious extra (4)

| Case | Transcript | Expects |
| --- | --- | --- |
| `extra-flashlight-and-joke` | "Turn on the flashlight and tell me a joke" | toggle_flashlight · toggle_flashlight.state |
| `extra-timer-and-weather` | "Set a timer for five minutes, and what's the weather like out there?" | set_timer · set_timer.minutes |
| `extra-self-correction` | "Set a timer for ten minutes — actually no, make it twenty" | set_timer · set_timer.minutes |
| `extra-two-legitimate-calls` | "What's on my calendar today, and remind me to water the plants" | read_next_events → create_reminder · create_reminder.due, create_reminder.title |

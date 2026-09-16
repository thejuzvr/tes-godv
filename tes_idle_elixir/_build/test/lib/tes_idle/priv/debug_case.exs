t1 = "Сапоги героя промокли раньше, чем герой проснулся."
t2 = "Моросил частый дождь."
IO.puts("t1 down: " <> String.downcase(t1))
IO.puts("t2 down: " <> String.downcase(t2))
IO.puts("t1 has сапог: " <> to_string(String.contains?(String.downcase(t1), "сапог")))
IO.puts("t2 has сапог: " <> to_string(String.contains?(String.downcase(t2), "сапог")))

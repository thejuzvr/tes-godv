# Единый вход сида данных: все частичные сиды в правильном порядке, идемпотентно.
# Запуск: mix run priv/seed_all.exs  (свежая БД: mix ecto.reset затем этот скрипт)
IO.puts("== seed_all: narratives ==")
Code.require_file("seed_narratives.exs", __DIR__)

IO.puts("== seed_all: phase2 ==")
Code.require_file("seed_phase2.exs", __DIR__)

IO.puts("== seed_all: fragments ==")
Code.require_file("seed_fragments.exs", __DIR__)

IO.puts("== seed_all: construction ==")
Code.require_file("seed_construction.exs", __DIR__)

IO.puts("== seed_all: guild_shop ==")
Code.require_file("seed_guild_shop.exs", __DIR__)

IO.puts("== seed_all: skyforge ==")
Code.require_file("seed_skyforge.exs", __DIR__)

IO.puts("== seed_all: guild_news ==")
Code.require_file("seed_guild_news.exs", __DIR__)

IO.puts("== seed_all: gates ==")
Code.require_file("seed_gates.exs", __DIR__)

IO.puts("== seed_all: content (pets catalog + items) ==")
Code.require_file("seed_content.exs", __DIR__)

IO.puts("== seed_all: monsters (bestiary, требует content) ==")
Code.require_file("seed_monsters.exs", __DIR__)

IO.puts("== seed_all: done ==")
:ok

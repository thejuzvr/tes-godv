# CD-1 разовый: считать @templates без запуска вставки
Code.require_file("priv/seed_narratives.exs")
tpls = SeedNarratives.templates()
IO.puts("COUNT=#{length(tpls)}")
System.halt(0)

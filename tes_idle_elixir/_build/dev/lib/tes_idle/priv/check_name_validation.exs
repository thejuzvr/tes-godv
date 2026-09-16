alias TesIdle.Schemas.Hero

bad = Hero.changeset(%Hero{}, %{"name" => "???????", "race" => "nord", "hero_class" => "warrior"})
good = Hero.changeset(%Hero{}, %{"name" => "Хальвар", "race" => "nord", "hero_class" => "warrior"})

IO.puts("mojibake valid: #{bad.valid?}")
IO.puts("normal valid: #{good.valid?}")
IO.inspect(bad.errors[:name])

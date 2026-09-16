hero_id = "0d2ed02b-c10c-4f95-9b0a-4192f9ceb5f1"
{:ok, result} = TesIdle.Game.Pipeline.tick(hero_id)
IO.puts("manual tick ok, state_to: #{inspect(result[:state_to])}")

configs = TesIdle.Game.ContextBuilder.load_configs()
cfg = TesIdle.Game.Journal.Throttle.config(configs)

body = %{
  throttle: Map.update!(cfg, :mode, &to_string/1),
  preview: TesIdle.Game.Journal.Retention.preview(configs),
  stats: TesIdle.Game.Journal.Aggregator.summary(Date.add(Date.utc_today(), -29), Date.utc_today())
}

IO.puts(Jason.encode!(body))

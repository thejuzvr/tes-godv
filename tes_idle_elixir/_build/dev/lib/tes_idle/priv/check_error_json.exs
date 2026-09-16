IO.inspect(TesIdleWeb.ErrorJSON.render("404.json", %{}), label: "404")
IO.inspect(TesIdleWeb.ErrorJSON.render("500.json", %{}), label: "500")
IO.inspect(TesIdleWeb.ErrorJSON.render("401.json", %{}), label: "401")
IO.inspect(TesIdleWeb.ErrorJSON.render("418.json", %{}), label: "418")

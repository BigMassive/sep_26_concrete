import Config

config :concrete_runtime, start_runtime: true

import_config "#{config_env()}.exs"

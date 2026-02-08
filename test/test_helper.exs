{:ok, _} = ADKExEcto.TestRepo.start_link()

# Run migrations in manual mode
Ecto.Migrator.up(ADKExEcto.TestRepo, 0, ADKExEcto.TestMigration, log: false)

ExUnit.start()

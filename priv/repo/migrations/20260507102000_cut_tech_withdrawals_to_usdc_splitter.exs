defmodule TechTree.Repo.Migrations.CutTechWithdrawalsToUsdcSplitter do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE tech_withdrawals DROP CONSTRAINT IF EXISTS tech_withdrawals_min_regent_out_check"

    execute "ALTER TABLE tech_withdrawals DROP CONSTRAINT IF EXISTS tech_withdrawals_min_usdc_out_check"

    execute "ALTER TABLE tech_withdrawals DROP CONSTRAINT IF EXISTS tech_withdrawals_regent_recipient_check"

    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'tech_withdrawals'
          AND column_name = 'min_regent_out'
      ) THEN
        IF NOT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_name = 'tech_withdrawals'
            AND column_name = 'min_usdc_out'
        ) THEN
          ALTER TABLE tech_withdrawals RENAME COLUMN min_regent_out TO min_usdc_out;
        ELSE
          UPDATE tech_withdrawals
          SET min_usdc_out = min_regent_out
          WHERE min_usdc_out IS NULL;

          ALTER TABLE tech_withdrawals DROP COLUMN min_regent_out;
        END IF;
      END IF;
    END $$;
    """

    execute "ALTER TABLE tech_withdrawals DROP COLUMN IF EXISTS regent_recipient"

    create constraint(:tech_withdrawals, :tech_withdrawals_min_usdc_out_check,
             check: "min_usdc_out ~ '^[1-9][0-9]*$'"
           )
  end

  def down do
    raise "hard cutover only"
  end
end

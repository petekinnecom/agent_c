# frozen_string_literal: true

module AgentC
  module Store
    extend ActiveSupport::Concern

    included do
      record(:workspace) do
        schema do |t|
          t.string(:dir, null: false)
          t.json(:env, default: [])
        end

        def self.ensure_created!(dir:, env:)
          find_or_create_by!(dir:).tap { _1.update!(env:) }
        end
      end

      record(:task) do
        schema do |t|
          t.string(:status, default: "pending")
          t.json(:completed_steps, default: [])
          t.string(:record_type)
          t.integer(:record_id)
          t.references(:workspace)

          t.string(:handler)

          t.string(:error_message)
          t.json(:chat_ids, default: [])

          t.timestamps
        end

        belongs_to(
          :record,
          polymorphic: true,
          required: false
        )

        belongs_to(
          :workspace,
          class_name: class_name(:workspace),
          required: false
        )

        def fail!(message)
          update!(
            status: "failed",
            error_message: message
          )
        end

        def done!
          update!(status: "done")
        end

        def done?
          status == "done"
        end

        def failed?
          status == "failed"
        end

        def pending?
          status == "pending"
        end
      end
    end
  end
end

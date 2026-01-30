# frozen_string_literal: true

class Pipeline < AgentC::Pipeline
  agent_step(:pick_a_random_file)
  agent_step(:summarize_the_file)
  agent_step(:write_summary_to_disk)

  step(:finalize) do
    if repo.uncommitted_changes?
      repo.commit_all(
        <<~TXT
          claude: added file: #{record.summary_path}
        TXT
      )
    else
      task.fail!("didn't create a file")
    end
  end
end

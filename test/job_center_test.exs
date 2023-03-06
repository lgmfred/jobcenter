defmodule JobCenterTest do
  use ExUnit.Case
  doctest JobCenter

  test "start_link/1 -> start the server" do
    {:ok, pid} = JobCenter.start_link([])
    assert Process.alive?(pid)
  end

  describe "add_job/2" do
    test "add to an empty queue" do
      {:ok, pid} = JobCenter.start_link([])
      fun = fn -> :empty end

      assert JobCenter.add_job(pid, fun, 2) == 1
      assert JobCenter.get_queue_list(pid) == [{1, fun, 2}]
    end

    test "add to queue with one or more element" do
      fun = fn -> :one_or_more end
      queue = [{1, fun, 3}, {2, fun, 2}]
      {:ok, pid} = JobCenter.start_link(id: 3, queue: queue)
      new_queue = [{1, fun, 3}, {2, fun, 2}, {3, fun, 1}]

      assert JobCenter.add_job(pid, fun, 1) == 3
      assert JobCenter.get_queue_list(pid) == new_queue
    end
  end

  describe "work_wanted/1" do
    test "request from empty queue" do
      {:ok, pid} = JobCenter.start_link()

      assert JobCenter.work_wanted(pid) == :no_work
    end

    test "request from a populated queue" do
      fun = fn -> :populated_queue end
      queue = [{1, fun, 2}, {2, fun, 1}]
      progress = Enum.reverse(queue)
      {:ok, pid} = JobCenter.start_link(id: 3, queue: queue)

      assert JobCenter.work_wanted(pid) == {1, fun, 2}
      assert JobCenter.work_wanted(pid) == {2, fun, 1}
      assert JobCenter.get_progress_list(pid) == progress
    end
  end

  describe "job_done/2" do
    test "signal with an invalid job number" do
      {:ok, pid} = JobCenter.start_link()

      assert JobCenter.job_done(pid, 1000) == :ok
      assert JobCenter.job_done(pid, :invalid) == :ok
    end

    test "signal with a valid job number" do
      fun = fn -> :done_invalid_id end
      queue = [{1, fun, 2}, {2, fun, 1}]
      {:ok, pid} = JobCenter.start_link(id: 3, queue: queue)
      {no1, _, _} = JobCenter.work_wanted(pid)
      {no2, _, _} = JobCenter.work_wanted(pid)

      assert JobCenter.job_done(pid, no1) == :ok
      assert JobCenter.get_done_list(pid) == [{1, fun, 2}]
      assert JobCenter.job_done(pid, no2) == :ok
      assert JobCenter.get_done_list(pid) == [{2, fun, 1}, {1, fun, 2}]
    end
  end

  describe "statistics/1" do
    test "with initial state" do
      {:ok, pid} = JobCenter.start_link()
      stats = %{queue: [], progress: [], done: []}

      assert JobCenter.statistics(pid) == stats
    end

    test "stats not empty lists" do
      fun = fn -> :stats end
      queue = [{1, fun, 3}, {2, fun, 2}, {3, fun, 1}]
      {:ok, pid} = JobCenter.start_link(id: 4, queue: queue)
      {id1, _, _} = JobCenter.work_wanted(pid)
      {_id2, _, _} = JobCenter.work_wanted(pid)
      :ok = JobCenter.job_done(pid, id1)
      stats = %{queue: [{3, fun, 1}], progress: [{2, fun, 2}], done: [{1, fun, 3}]}

      assert JobCenter.statistics(pid) == stats
    end
  end

  describe "monitor workers" do
    ## If a worker dies, jobs it was doing are returned to the queue
    test "one worker dies" do
      fun = fn -> :one_worker end
      queue = generate_jobs(1..3, fun)
      {:ok, pid} = JobCenter.start_link(id: 4, queue: queue)
      worker_pid = spawn(fn -> req3_do1_and_die(pid) end)
      Process.sleep(100)
      %{queue: [], progress: p1, done: d1} = JobCenter.statistics(pid)
      true = Process.exit(worker_pid, :kill)
      Process.sleep(100)
      %{queue: q2, progress: [], done: d2} = JobCenter.statistics(pid)

      assert p1 == [{1, fun, 3}, {3, fun, 1}]
      assert d1 == [{2, fun, 2}]
      assert q2 == [{1, fun, 3}, {3, fun, 1}]
      assert d2 == [{2, fun, 2}]
    end

    test "more than one workers die" do
      fun = fn -> :more_worker end
      queue = generate_jobs(1..9, fun)
      {:ok, pid} = JobCenter.start_link(id: 10, queue: queue)
      worker1 = spawn(fn -> req3_do1_and_die(pid) end)
      Process.sleep(100)
      worker2 = spawn(fn -> req3_do1_and_die(pid) end)
      Process.sleep(100)
      worker3 = spawn(fn -> req3_do1_and_die(pid) end)
      Process.sleep(100)
      %{queue: [], progress: p1, done: d1} = JobCenter.statistics(pid)
      for w_pid <- [worker1, worker2, worker3], do: Process.exit(w_pid, :kill)
      Process.sleep(100)
      %{queue: q2, progress: [], done: d2} = JobCenter.statistics(pid)

      expected1 = [{1, fun, 9}, {3, fun, 7}, {4, fun, 6}, {6, fun, 4}, {7, fun, 3}, {9, fun, 1}]
      expected2 = [{2, fun, 8}, {5, fun, 5}, {8, fun, 2}]

      assert p1 == expected1
      assert d1 == expected2
      assert q2 == expected1
      assert d2 == expected2
    end
  end

  ## Test Helper Functions
  defp req3_do1_and_die(pid) do
    [_, {id2, _fun, _time}, _] = for _n <- 1..3, do: JobCenter.work_wanted(pid)
    JobCenter.job_done(pid, id2)
    Process.sleep(5000)
  end

  defp generate_jobs(a..z, fun) do
    Enum.zip_reduce(a..z, z..a, [], fn el1, el2, acc -> [{el1, fun, el2} | acc] end)
  end
end

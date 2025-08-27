-- ~/.config/nvim/lua/todo_workflow.lua

local M = {} -- This table will hold all our public functions

-- Helper function to get current date formatted as DD.MM.YYYY
function M.get_current_date_header()
    local date_str = vim.fn.strftime("%d.%m.%Y")
    return "## " .. date_str
end

-- Helper to find the line number of a section (e.g., "## Todos" or "## 28.06.2025")
-- Returns line_num (0-indexed) or nil if not found
function M.find_section_line(buffer_lines, section_header)
    for i, line in ipairs(buffer_lines) do
        if line:match("^" .. section_header .. "$") then
            return i - 1 -- Return 0-indexed line number
        end
    end
    return nil
end

-- Finishes a plain todo or ticks a habit count.
-- Behaviour:
-- - If line is "[N] ..." with N>1: decrement to [N-1] in place
-- - If line is "[1] ..." (or 0/invalid): convert to [x] and move to today's section
-- - If line is "[ ] ...": convert to [x] and move to today's section
function M.finish_todo_item()
    local current_line_num = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed line
    local current_line = vim.api.nvim_get_current_line()

    -- 1. If it's a habit line like "[N] ..." then tick/decrement first
    local habit_count_str = current_line:match("^%s*%[(%d+)%]%s.*")
    if habit_count_str then
        local habit_count = tonumber(habit_count_str) or 0
        if habit_count > 1 then
            -- Decrement in place
            local updated_line = current_line:gsub("%[(%d+)%]", "[" .. tostring(habit_count - 1) .. "]", 1)
            vim.api.nvim_set_current_line(updated_line)

            -- Also log a completion entry for today without removing from Todos
            local completed_task_line_for_log = current_line:gsub("%b[]", "[x]", 1)
            local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            local date_header = M.get_current_date_header()
            local date_section_line_num = M.find_section_line(buffer_lines, date_header)

            if not date_section_line_num then
                -- Create today's section above "## Todos" or after the last header
                local todos_section_line_num = M.find_section_line(buffer_lines, "## Todos")
                local insert_pos
                if todos_section_line_num then
                    insert_pos = todos_section_line_num
                else
                    insert_pos = 0
                    for i = #buffer_lines, 1, -1 do
                        if buffer_lines[i]:match("^#%#?%s.*") then
                            insert_pos = i
                            break
                        end
                    end
                end
                table.insert(buffer_lines, insert_pos + 1, date_header)
                table.insert(buffer_lines, insert_pos + 2, "")
                table.insert(buffer_lines, insert_pos + 3, completed_task_line_for_log)
            else
                -- Append under existing today's section
                local insert_pos = date_section_line_num + 1
                while insert_pos < #buffer_lines and not buffer_lines[insert_pos + 1]:match("^##%s.*") do
                    insert_pos = insert_pos + 1
                end
                table.insert(buffer_lines, insert_pos + 1, completed_task_line_for_log)
            end

            vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)

            print("Habit ticked and logged: " .. tostring(habit_count - 1) .. " remaining")
            return
        end
        -- Count is 1 (or invalid/0): finalize as completed and move below (falls through)
    end

    -- 2. Check if the current line is an uncompleted plain task or a habit reaching completion
    if not current_line:match("^%s*%[%s*%]%s.*") and not habit_count_str then
        print("Not a todo/habit item. Place cursor on a '[ ]' or '[N]' line.")
        return
    end

    -- 3. Mark as completed and store it
    local completed_task_line
    if habit_count_str then
        completed_task_line = current_line:gsub("%b[]", "[x]", 1)
    else
        completed_task_line = current_line:gsub("%[%s*%]", "[x]")
    end
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Get all lines

    -- 4. Remove the task from its current position
    table.remove(buffer_lines, current_line_num + 1) -- Lua tables are 1-indexed

    -- 5. Find or create the ## <Current Date> section
    local date_header = M.get_current_date_header()
    local date_section_line_num = M.find_section_line(buffer_lines, date_header)

    if not date_section_line_num then
        -- Date section doesn't exist, create it above "## Todos" or at the end
        local todos_section_line_num = M.find_section_line(buffer_lines, "## Todos")
        local insert_pos

        if todos_section_line_num then
            -- Insert above ## Todos section (or before "## Todos" content starts)
            insert_pos = todos_section_line_num
        else
            -- No ## Todos, insert at the end of the file (or after # Todo Timothy if it's the only one)
            insert_pos = 0 -- Default to top if no headers.
            for i = #buffer_lines, 1, -1 do
                if buffer_lines[i]:match("^#%#?%s.*") then -- Find the last header
                    insert_pos = i
                    break
                end
            end
        end

        -- Insert header, empty line, and the task
        table.insert(buffer_lines, insert_pos + 1, date_header)
        table.insert(buffer_lines, insert_pos + 2, "") -- Add an empty line for spacing
        table.insert(buffer_lines, insert_pos + 3, completed_task_line)
    else
        -- Date section exists, insert the task below it
        local insert_pos = date_section_line_num + 1 -- Start searching from here (after the date header)
        while insert_pos < #buffer_lines and not buffer_lines[insert_pos + 1]:match("^##%s.*") do
            insert_pos = insert_pos + 1
        end
        table.insert(buffer_lines, insert_pos + 1, completed_task_line)
    end

    -- 6. Update the buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)

    print("Task finished and moved!")
end

-- Function to handle creating a new todo item ("ni")
function M.new_todo_item()
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Get all lines

    -- 1. Find the ## Todos section
    local todos_section_line_num = M.find_section_line(buffer_lines, "## Todos")

    if not todos_section_line_num then
        print("Error: '## Todos' section not found. Please create it first.")
        return
    end

    -- Determine the insertion point (1-indexed for Lua table)
    -- We'll try to find the last OPEN todo item. If none, then right after the header.
    local insertion_point_idx = todos_section_line_num + 1 -- Default to right after "## Todos" header

    local found_open_task = false
    -- Iterate through lines STARTING FROM AFTER the "## Todos" header
    for i = todos_section_line_num + 1, #buffer_lines do
        local line = buffer_lines[i]

        -- If we encounter another header, we've gone past the "## Todos" section
        if line:match("^##%s.*") then
            break
        end

        -- If it's an UNCOMPLETED task, update our potential insertion point
        if line:match("^%s*%[%s*%]%s.*") then
            insertion_point_idx = i -- This is the line of the open task
            found_open_task = true
        end
        -- We continue iterating even after finding an open task,
        -- to ensure we find the *last* open task.
    end

    -- After the loop, insertion_point_idx holds:
    -- - The line number of the *last open task* if found.
    -- - The line number of the `## Todos` header + 1 if no open tasks were found
    --   within the section, meaning it's either empty or only has completed tasks.

    -- Insert the new task line *after* the determined insertion_point_idx
    table.insert(buffer_lines, insertion_point_idx + 1, "[ ] ")

    -- 3. Update the buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)

    -- 4. Place cursor on the new line for editing
    -- The new line was inserted at `insertion_point_idx + 1`.
    -- So its 1-indexed row number is `insertion_point_idx + 1`.
    -- The column should be after "[ ] " (4 characters), so 5.
    vim.api.nvim_win_set_cursor(0, {insertion_point_idx + 1, 4}) -- Row, Col
    vim.cmd("startinsert") -- Enter Insert mode
end

-- Function to handle creating a new habit item ("nh") with default count 16
function M.new_habit_item()
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    -- 1. Find the ## Todos section
    local todos_section_line_num = M.find_section_line(buffer_lines, "## Todos")

    if not todos_section_line_num then
        print("Error: '## Todos' section not found. Please create it first.")
        return
    end

    -- Determine insertion point after the last open item within the Todos section
    local insertion_point_idx = todos_section_line_num + 1
    for i = todos_section_line_num + 1, #buffer_lines do
        local line = buffer_lines[i]
        if line:match("^##%s.*") then
            break
        end
        if line:match("^%s*%[%s*%]%s.*") or line:match("^%s*%[(%d+)%]%s.*") then
            insertion_point_idx = i
        end
    end

    -- 2. Insert new habit with default 16 ticks remaining
    local head = "[16] "
    table.insert(buffer_lines, insertion_point_idx + 1, head)

    -- 3. Update buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)

    -- 4. Place cursor to start typing the habit title
    vim.api.nvim_win_set_cursor(0, { insertion_point_idx + 1, #head })
    vim.cmd("startinsert")
end

-- This is crucial: return the module table so it can be required
return M

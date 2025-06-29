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

-- ~/.config/nvim/lua/todo_workflow.lua

-- ... (M.get_current_date_header and M.find_section_line functions are the same) ...

-- Function to handle finishing a todo item ("xx")
function M.finish_todo_item()
    local current_line_num = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed line
    local current_line = vim.api.nvim_get_current_line()

    -- 1. Check if the current line is an uncompleted task
    if not current_line:match("^%s*%[%s*%]%s.*") then
        print("Not an uncompleted task. Cursor must be on a '[ ]' item.")
        return
    end

    -- 2. Mark as completed and store it
    local completed_task_line = current_line:gsub("%[%s*%]", "[x]")
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Get all lines

    -- 3. Remove the task from its current position
    table.remove(buffer_lines, current_line_num + 1) -- Lua tables are 1-indexed

    -- 4. Find or create the ## <Current Date> section
    local date_header = M.get_current_date_header()
    local date_section_line_num = M.find_section_line(buffer_lines, date_header)

    local target_insert_line_idx_0_indexed -- This will be the line *before* where the new task goes

    if not date_section_line_num then
        -- Date section doesn't exist, create it.
        local todos_section_line_num = M.find_section_line(buffer_lines, "## Todos")
        local new_date_section_start_line_idx_0_indexed

        if todos_section_line_num then
            -- Insert above ## Todos section
            new_date_section_start_line_idx_0_indexed = todos_section_line_num
        else
            -- No ## Todos, find the last header or insert at the end of the file
            new_date_section_start_line_idx_0_indexed = 0 -- Default to top if no headers.
            for i = #buffer_lines, 1, -1 do
                if buffer_lines[i]:match("^#%#?%s.*") then -- Find the last header
                    new_date_section_start_line_idx_0_indexed = i
                    break
                end
            end
        end

        -- Insert header
        table.insert(buffer_lines, new_date_section_start_line_idx_0_indexed + 1, date_header)
        -- The task will be inserted right after this header
        target_insert_line_idx_0_indexed = new_date_section_start_line_idx_0_indexed + 1

    else
        -- Date section already exists.
        -- Find the last line within this date section.
        local end_of_date_section_content_idx_0_indexed = date_section_line_num

        -- Loop through lines after the date header until next header or EOF
        for i = date_section_line_num + 1, #buffer_lines - 1 do -- -1 because buffer_lines is 1-indexed
            local line = buffer_lines[i + 1] -- i+1 for 1-indexed access
            if line:match("^##%s.*") then -- Next header found, stop
                break
            end
            end_of_date_section_content_idx_0_indexed = i -- Update to current line if it's part of the section
        end
        target_insert_line_idx_0_indexed = end_of_date_section_content_idx_0_indexed
    end

    -- Now, insert the completed task at the determined position
    table.insert(buffer_lines, target_insert_line_idx_0_indexed + 1, completed_task_line)


    -- --- BLANK LINE INSERTION LOGIC (REFINED) ---
    -- After inserting the completed task, let's determine if a blank line is needed
    -- *after* the date section's content and *before* the next header.

    -- Refresh buffer_lines after the insertion
    buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    -- Find the line number of the date section header again (it might have shifted)
    local actual_date_header_line_num = M.find_section_line(buffer_lines, date_header)

    if actual_date_header_line_num then
        local last_content_line_in_date_section_idx = actual_date_header_line_num
        -- Find the actual last line of content (not blank, not header) in this date section
        for i = actual_date_header_line_num + 1, #buffer_lines - 1 do
            local line = buffer_lines[i + 1]
            if line:match("^##%s.*") then -- Next header found, this is the end of the section
                break
            end
            last_content_line_in_date_section_idx = i -- This line is part of the content
        end

        -- Check the line immediately after the last content line of the date section
        local line_after_date_section_content_idx = last_content_line_in_date_section_idx + 1

        -- Ensure it's within buffer bounds AND that it's a header AND the line before it is not blank
        if line_after_date_section_content_idx <= #buffer_lines then
            local next_line = buffer_lines[line_after_date_section_content_idx]
            local line_before_next_header = buffer_lines[line_after_date_section_content_idx - 1]

            if next_line:match("^##%s.*") and not line_before_next_header:match("^%s*$") then
                 -- We are exactly before a header, and the previous line is not blank.
                 -- Insert a blank line at this exact position.
                table.insert(buffer_lines, line_after_date_section_content_idx, "")
            end
        end
    end
    -- --- END BLANK LINE LOGIC ---


    -- 5. Update the buffer with all changes
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

-- This is crucial: return the module table so it can be required
return M

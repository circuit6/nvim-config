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

--- Ensures consistent spacing around ## headers.
--- Each ## header should have one empty line above it and one below it.
--- This function handles buffer modifications directly.
function M.clean_up_structure()
    local original_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Get all lines
    local lines_to_write = {}
    local modified = false

    for i = 1, #original_lines do
        local current_line = original_lines[i]
        local prev_line = original_lines[i - 1] or ""
        local next_line = original_lines[i + 1] or ""

        if current_line:match("^##%s.*") then -- Found a ## header
            -- Add empty line above if not already present and not the very first line
            if i > 1 and prev_line ~= "" then
                table.insert(lines_to_write, "")
                modified = true
            end

            table.insert(lines_to_write, current_line)

            -- Add empty line below if not already present and not the very last line
            if i < #original_lines and next_line ~= "" then
                table.insert(lines_to_write, "")
                modified = true
            end
        elseif current_line == "" then
            -- Logic to remove redundant empty lines, but preserve those for header spacing
            local prev_is_header = prev_line:match("^##%s.*")
            local next_is_header = next_line:match("^##%s.*")
            local prev_is_empty = prev_line == ""
            local next_is_empty = next_line == ""

            if (prev_is_header and not next_is_empty) or (next_is_header and not prev_is_empty) then
                -- This empty line is serving as spacing for a header, keep it
                table.insert(lines_to_write, current_line)
            elseif not prev_is_empty then -- If previous line is NOT empty, we can add this empty line (it's not consecutive)
                table.insert(lines_to_write, current_line)
            else
                -- This is a redundant empty line, do not add it
                modified = true
            end
        else
            table.insert(lines_to_write, current_line)
        end
    end

    -- Final pass to ensure no trailing empty lines unless they are header spacing
    while #lines_to_write > 0 and lines_to_write[#lines_to_write] == "" do
        if #lines_to_write > 1 and lines_to_write[#lines_to_write - 1]:match("^##%s.*") then
            -- This empty line is below a header, so keep it for spacing
            break
        else
            table.remove(lines_to_write)
            modified = true
        end
    end

    -- Only update the buffer if changes were made
    if modified or #original_lines ~= #lines_to_write then
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines_to_write)
        print("Buffer structure cleaned up!")
    else
        print("No structure cleanup needed.")
    end
end


-- Function to handle finishing a todo item ("xx")
function M.finish_todo_item()
    local original_cursor_pos = vim.api.nvim_win_get_cursor(0) -- Get original cursor position
    local current_line_num_0_indexed = original_cursor_pos[1] - 1
    local current_col_num = original_cursor_pos[2]
    local current_line_content = vim.api.nvim_get_current_line() -- Get content to potentially re-find it

    -- 1. Check if the current line is an uncompleted task
    if not current_line_content:match("^%s*%[%s*%]%s.*") then
        print("Not an uncompleted task. Cursor must be on a '[ ]' item.")
        return
    end

    -- 2. Mark as completed and store it
    local completed_task_line = current_line_content:gsub("%[%s*%]", "[x]")
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Get all lines

    -- 3. Remove the task from its current position
    table.remove(buffer_lines, current_line_num_0_indexed + 1) -- Lua tables are 1-indexed

    -- 4. Find or create the ## <Current Date> section
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
            -- No ## Todos, insert at the end of the file
            insert_pos = #buffer_lines
        end

        -- Insert header, empty line, and the task
        table.insert(buffer_lines, insert_pos + 1, date_header)
        table.insert(buffer_lines, insert_pos + 2, "") -- Add an empty line for spacing
        table.insert(buffer_lines, insert_pos + 3, completed_task_line)
    else
        -- Date section exists, insert the task below it
        local insert_pos = date_section_line_num + 1 -- Start searching from here (after the date header)
        while insert_pos <= #buffer_lines and not buffer_lines[insert_pos]:match("^##%s.*") do
            insert_pos = insert_pos + 1
        end
        table.insert(buffer_lines, insert_pos, completed_task_line)
    end

    -- 5. Update the buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)

    -- --- CURSOR PLACEMENT LOGIC ---
    -- Goal for 'xx': Stay on the line that was originally below it,
    -- or the line that replaced the removed line, or the previous line if removed was last.
    local new_cursor_row_0_indexed = math.min(current_line_num_0_indexed, vim.api.nvim_buf_line_count(0) - 1)
    if new_cursor_row_0_indexed < 0 then new_cursor_row_0_indexed = 0 end -- Ensure non-negative

    local final_line_content = vim.api.nvim_buf_get_lines(0, new_cursor_row_0_indexed, new_cursor_row_0_indexed + 1, false)[1] or ""
    local final_cursor_col = math.min(current_col_num, #final_line_content)

    vim.api.nvim_win_set_cursor(0, {new_cursor_row_0_indexed + 1, final_cursor_col})

    print("Task finished and moved!")
end

-- Function to handle creating a new todo item ("ni")
function M.new_todo_item()
    -- IMPORTANT: Re-get buffer_lines here to ensure we have the most current state
    -- especially since clean_up_structure is no longer called before this.
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    -- 1. Find the ## Todos section
    local todos_section_line_num = M.find_section_line(buffer_lines, "## Todos")

    if not todos_section_line_num then
        print("Error: '## Todos' section not found. Please create it first.")
        return
    end

    -- Determine the insertion point (1-indexed for Lua table)
    local insertion_point_idx = todos_section_line_num + 1 -- Default to right after "## Todos" header

    -- Iterate through lines STARTING FROM AFTER the "## Todos" header
    for i = todos_section_line_num + 1, #buffer_lines do
        local line = buffer_lines[i]

        -- If we encounter another header, we've gone past the "## Todos" section
        if line:match("^##%s.*") then
            break
        end

        -- If it's an UNCOMPLETED task, update our potential insertion point
        if line:match("^%s*%[%s*%]%s.*") then
            insertion_point_idx = i -- This is the line of the last open task
        end
    end

    -- Insert the new task line *after* the determined insertion_point_idx
    table.insert(buffer_lines, insertion_point_idx + 1, "[ ] ")

    -- 3. Update the buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)

    -- --- CURSOR PLACEMENT LOGIC ---
    -- Goal for 'ni': Place cursor on the newly created item and enter insert mode.
    local cursor_row = insertion_point_idx + 1
    local cursor_col = 4 -- After "[ ] "
    vim.api.nvim_win_set_cursor(0, {cursor_row, cursor_col})
    vim.cmd("startinsert") -- Enter Insert mode

    print("New task created!")
end

-- This is crucial: return the module table so it can be required
return M

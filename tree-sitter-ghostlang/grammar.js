// Tree-sitter grammar for Ghostlang v0.1.0
// Supports dual syntax: Lua-style and C-style

module.exports = grammar({
  name: 'ghostlang',

  rules: {
    source_file: $ => repeat(choice(
      $.variable_declaration,
      $.local_variable_declaration,
      $.function_declaration,
      $.local_function_declaration,
      $.if_statement,
      $.while_statement,
      $.for_statement,
      $.repeat_statement,
      $.expression_statement,
      $.block_statement,
      $.return_statement,
      $.break_statement,
      $.continue_statement,
      $.comment
    )),

    statement: $ => choice(
      $.variable_declaration,
      $.local_variable_declaration,
      $.function_declaration,
      $.local_function_declaration,
      $.if_statement,
      $.while_statement,
      $.for_statement,
      $.repeat_statement,
      $.expression_statement,
      $.block_statement,
      $.return_statement,
      $.break_statement,
      $.continue_statement,
      $.empty_statement
    ),

    // Variable declarations: var x = 5; or var x = 5 (Lua-style)
    variable_declaration: $ => prec.right(seq(
      'var',
      field('name', $.identifier),
      '=',
      field('value', $._expression_base),
      optional(';')
    )),

    // Local variable declarations: local x = 5
    local_variable_declaration: $ => prec.right(seq(
      'local',
      field('name', $.identifier),
      '=',
      field('value', $._expression_base),
      optional(';')
    )),

    // Variable declarations without semicolon (for use in for loops)
    for_variable_declaration: $ => seq(
      'var',
      field('name', $.identifier),
      '=',
      field('value', $._expression_base)
    ),

    // Function declarations: function name() { ... } or function name() ... end
    function_declaration: $ => choice(
      // C-style: function name() { ... }
      seq(
        'function',
        field('name', $.identifier),
        field('parameters', $.parameter_list),
        field('body', $.block_statement)
      ),
      // Lua-style: function name() ... end
      seq(
        'function',
        field('name', $.identifier),
        field('parameters', $.parameter_list),
        field('body', $.lua_block)
      )
    ),

    // Local function declarations: local function name() ... end
    local_function_declaration: $ => seq(
      'local',
      'function',
      field('name', $.identifier),
      field('parameters', $.parameter_list),
      field('body', $.lua_block)
    ),

    parameter_list: $ => seq(
      '(',
      optional(seq(
        $.identifier,
        repeat(seq(',', $.identifier))
      )),
      ')'
    ),

    // Lua-style block: statements ... end
    lua_block: $ => seq(
      repeat(choice(
        $.variable_declaration,
        $.local_variable_declaration,
        $.function_declaration,
        $.local_function_declaration,
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.repeat_statement,
        $.expression_statement,
        $.return_statement,
        $.break_statement,
        $.continue_statement
      )),
      'end'
    ),

    // Control flow statements - dual syntax support
    if_statement: $ => prec.right(choice(
      // C-style: if (cond) { } else { }
      seq(
        'if',
        '(',
        field('condition', $._expression_base),
        ')',
        field('then', choice(
          $.variable_declaration,
          $.function_declaration,
          $.if_statement,
          $.while_statement,
          $.for_statement,
          $.repeat_statement,
          $.expression_statement,
          $.block_statement,
          $.return_statement,
          $.break_statement,
          $.continue_statement,
          $.empty_statement
        )),
        optional(seq('else', field('else', choice(
          $.variable_declaration,
          $.function_declaration,
          $.if_statement,
          $.while_statement,
          $.for_statement,
          $.repeat_statement,
          $.expression_statement,
          $.block_statement,
          $.return_statement,
          $.break_statement,
          $.continue_statement,
          $.empty_statement
        ))))
      ),
      // Lua-style: if cond then ... elseif ... else ... end
      seq(
        'if',
        field('condition', $._expression_base),
        'then',
        repeat(choice(
          $.variable_declaration,
          $.local_variable_declaration,
          $.function_declaration,
          $.local_function_declaration,
          $.if_statement,
          $.while_statement,
          $.for_statement,
          $.repeat_statement,
          $.expression_statement,
          $.return_statement,
          $.break_statement,
          $.continue_statement
        )),
        repeat(seq(
          'elseif',
          field('elseif_condition', $._expression_base),
          'then',
          repeat(choice(
            $.variable_declaration,
            $.local_variable_declaration,
            $.function_declaration,
            $.local_function_declaration,
            $.if_statement,
            $.while_statement,
            $.for_statement,
            $.repeat_statement,
            $.expression_statement,
            $.return_statement,
            $.break_statement,
            $.continue_statement
          ))
        )),
        optional(seq(
          'else',
          repeat(choice(
            $.variable_declaration,
            $.local_variable_declaration,
            $.function_declaration,
            $.local_function_declaration,
            $.if_statement,
            $.while_statement,
            $.for_statement,
            $.repeat_statement,
            $.expression_statement,
            $.return_statement,
            $.break_statement,
            $.continue_statement
          ))
        )),
        'end'
      )
    )),

    while_statement: $ => choice(
      // C-style: while (cond) { ... }
      seq(
        'while',
        '(',
        field('condition', $._expression_base),
        ')',
        field('body', choice(
          $.variable_declaration,
          $.function_declaration,
          $.if_statement,
          $.while_statement,
          $.for_statement,
          $.repeat_statement,
          $.expression_statement,
          $.block_statement,
          $.return_statement,
          $.break_statement,
          $.continue_statement,
          $.empty_statement
        ))
      ),
      // Lua-style: while cond do ... end
      seq(
        'while',
        field('condition', $._expression_base),
        'do',
        repeat(choice(
          $.variable_declaration,
          $.local_variable_declaration,
          $.function_declaration,
          $.local_function_declaration,
          $.if_statement,
          $.while_statement,
          $.for_statement,
          $.repeat_statement,
          $.expression_statement,
          $.return_statement,
          $.break_statement,
          $.continue_statement
        )),
        'end'
      )
    ),

    // Repeat-until statement (Lua-style only)
    repeat_statement: $ => seq(
      'repeat',
      repeat(choice(
        $.variable_declaration,
        $.local_variable_declaration,
        $.function_declaration,
        $.local_function_declaration,
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.repeat_statement,
        $.expression_statement,
        $.return_statement,
        $.break_statement,
        $.continue_statement
      )),
      'until',
      field('condition', $._expression_base)
    ),

    for_statement: $ => prec(10, choice(
      // C-style: for (init; cond; update) { ... }
      seq(
        'for',
        '(',
        choice(
          seq(
            field('init', optional(alias($.for_variable_declaration, $.variable_declaration))),
            ';',
            field('condition', optional($._expression_base)),
            ';',
            field('update', optional($._expression_base))
          ),
          seq(
            'var',
            field('variable', $.identifier),
            'in',
            field('iterable', $._expression_base)
          )
        ),
        ')',
        field('body', choice(
          $.variable_declaration,
          $.function_declaration,
          $.if_statement,
          $.while_statement,
          $.for_statement,
          $.repeat_statement,
          $.expression_statement,
          $.block_statement,
          $.return_statement,
          $.break_statement,
          $.continue_statement,
          $.empty_statement
        ))
      ),
      // Lua-style numeric for: for i = start, end, step do ... end
      seq(
        'for',
        field('variable', $.identifier),
        '=',
        field('start', $._expression_base),
        ',',
        field('end', $._expression_base),
        optional(seq(',', field('step', $._expression_base))),
        'do',
        repeat(choice(
          $.variable_declaration,
          $.local_variable_declaration,
          $.function_declaration,
          $.local_function_declaration,
          $.if_statement,
          $.while_statement,
          $.for_statement,
          $.repeat_statement,
          $.expression_statement,
          $.return_statement,
          $.break_statement,
          $.continue_statement
        )),
        'end'
      ),
      // Lua-style generic for: for k, v in pairs(t) do ... end
      seq(
        'for',
        field('variables', seq(
          $.identifier,
          repeat(seq(',', $.identifier))
        )),
        'in',
        field('iterator', $._expression_base),
        'do',
        repeat(choice(
          $.variable_declaration,
          $.local_variable_declaration,
          $.function_declaration,
          $.local_function_declaration,
          $.if_statement,
          $.while_statement,
          $.for_statement,
          $.repeat_statement,
          $.expression_statement,
          $.return_statement,
          $.break_statement,
          $.continue_statement
        )),
        'end'
      )
    )),

    return_statement: $ => prec.right(seq(
      'return',
      optional(seq(
        $._expression_base,
        repeat(seq(',', $._expression_base))
      )),
      optional(';')
    )),

    break_statement: $ => prec.right(seq('break', optional(';'))),

    continue_statement: $ => prec.right(seq('continue', optional(';'))),

    expression_statement: $ => prec.left(seq(
      $._expression_base,
      optional(';')
    )),

    block_statement: $ => seq(
      '{',
      repeat(choice(
        $.variable_declaration,
        $.function_declaration,
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.expression_statement,
        $.block_statement,
        $.return_statement,
        $.comment
      )),
      '}'
    ),

    empty_statement: $ => ';',

    // Base expression rule that matches test expectations
    _expression_base: $ => choice(
      $.assignment_expression,
      $.conditional_expression,
      $.logical_or_expression,
      $.logical_and_expression,
      $.equality_expression,
      $.relational_expression,
      $.concat_expression,
      $.additive_expression,
      $.multiplicative_expression,
      $.unary_expression,
      $.call_expression,
      $.member_expression,
      $.subscript_expression,
      $.object_literal,
      $.array_literal,
      $.identifier,
      $.number_literal,
      $.string_literal,
      $.boolean_literal,
      $.null_literal,
      seq('(', $._expression_base, ')')
    ),

    // Expressions
    expression: $ => $._expression_base,

    assignment_expression: $ => prec.right(1, choice(
      seq(
        field('left', $._expression_base),
        field('operator', alias(choice('=', '+=', '-=', '*=', '/='), $.string)),
        field('right', $._expression_base)
      ),
      seq(
        field('left', $._expression_base),
        field('operator', alias(choice('++', '--'), $.string))
      )
    )),

    conditional_expression: $ => prec.right(2, seq(
      $._expression_base,
      '?',
      $._expression_base,
      ':',
      $._expression_base
    )),

    logical_or_expression: $ => prec.left(3, seq(
      $._expression_base, choice('||', 'or'), $._expression_base
    )),

    logical_and_expression: $ => prec.left(4, seq(
      $._expression_base, choice('&&', 'and'), $._expression_base
    )),

    equality_expression: $ => prec.left(5, seq(
      $._expression_base, choice('==', '!=', '~='), $._expression_base
    )),

    relational_expression: $ => prec.left(6, seq(
      $._expression_base, choice('<', '>', '<=', '>='), $._expression_base
    )),

    additive_expression: $ => prec.left(7, seq(
      $._expression_base, choice('+', '-'), $._expression_base
    )),

    // String concatenation (Lua-style ..)
    concat_expression: $ => prec.left(7, seq(
      $._expression_base, '..', $._expression_base
    )),

    multiplicative_expression: $ => prec.left(8, seq(
      $._expression_base, choice('*', '/', '%'), $._expression_base
    )),

    unary_expression: $ => prec(9, seq(
      choice('+', '-', '!', 'not'), $._expression_base
    )),

    call_expression: $ => prec.left(10, seq(
      field('function', $._expression_base),
      field('arguments', $.argument_list)
    )),

    member_expression: $ => prec.left(10, seq(
      field('object', $._expression_base),
      '.',
      field('property', $.identifier)
    )),

    subscript_expression: $ => prec.left(10, seq(
      field('object', $._expression_base),
      '[',
      field('index', $._expression_base),
      ']'
    )),

    argument_list: $ => seq(
      '(',
      optional(seq(
        $._expression_base,
        repeat(seq(',', $._expression_base))
      )),
      ')'
    ),


    // Object literals: { key: value, ... }
    object_literal: $ => seq(
      '{',
      optional(seq(
        $.object_member,
        repeat(seq(',', $.object_member)),
        optional(',')
      )),
      '}'
    ),

    object_member: $ => seq(
      choice(
        $.identifier,
        $.string_literal
      ),
      ':',
      $._expression_base
    ),

    // Array literals: [1, 2, 3]
    array_literal: $ => seq(
      '[',
      optional(seq(
        $._expression_base,
        repeat(seq(',', $._expression_base)),
        optional(',')
      )),
      ']'
    ),

    // Literals
    identifier: $ => token(prec(-1, /[a-zA-Z_][a-zA-Z0-9_]*/)),

    number_literal: $ => choice(
      /\d+/,
      /\d+\.\d+/,
      /\d*\.?\d+[eE][+-]?\d+/
    ),

    string_literal: $ => choice(
      seq('"', repeat(choice(/[^"\\]/, $.escape_sequence)), '"'),
      seq("'", repeat(choice(/[^'\\]/, $.escape_sequence)), "'")
    ),

    escape_sequence: $ => seq(
      '\\',
      choice(
        /[\\'"nrtbfav0]/,
        /x[0-9a-fA-F]{2}/,
        /u[0-9a-fA-F]{4}/,
        /U[0-9a-fA-F]{8}/
      )
    ),

    boolean_literal: $ => choice('true', 'false'),
    null_literal: $ => 'null',

    // Comments - C-style and Lua-style
    comment: $ => token(choice(
      // C-style single-line
      seq('//', /.*/),
      // C-style multi-line
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/'),
      // Lua-style single-line
      seq('--', /.*/)
    )),

    // Whitespace
    _whitespace: $ => /\s+/
  },

  extras: $ => [
    $.comment,
    $._whitespace
  ],

  conflicts: $ => [
    // Handle potential ambiguities between C-style and Lua-style constructs
    [$.block_statement, $.object_literal],
    [$.expression],
    [$.statement, $.function_declaration],
    [$.if_statement, $._expression_base],
    [$.while_statement, $._expression_base]
  ],

  word: $ => $.identifier
});
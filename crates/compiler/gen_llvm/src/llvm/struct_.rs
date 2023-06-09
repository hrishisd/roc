//! Representation of structs in the generated LLVM IR.

use bumpalo::collections::Vec as AVec;
use inkwell::{
    types::{BasicType, BasicTypeEnum, StructType},
    values::{BasicValue, BasicValueEnum, StructValue},
};
use roc_module::symbol::Symbol;
use roc_mono::layout::{InLayout, LayoutInterner, LayoutRepr, STLayoutInterner};

use crate::llvm::build::use_roc_value;

use super::{
    build::{BuilderExt, Env},
    convert::basic_type_from_layout,
    scope::Scope,
};

pub(crate) enum RocStructType<'ctx> {
    /// The roc struct should be passed by rvalue.
    ByValue(StructType<'ctx>),
}

impl<'ctx> Into<BasicTypeEnum<'ctx>> for RocStructType<'ctx> {
    fn into(self) -> BasicTypeEnum<'ctx> {
        self.as_basic_type_enum()
    }
}

impl<'ctx> RocStructType<'ctx> {
    pub fn build<'a>(
        env: &Env<'a, 'ctx, '_>,
        layout_interner: &mut STLayoutInterner<'a>,
        fields: &[InLayout<'_>],
    ) -> Self {
        let struct_type = basic_type_from_record(env, layout_interner, fields);
        RocStructType::ByValue(struct_type)
    }

    pub fn as_basic_type_enum(&self) -> BasicTypeEnum<'ctx> {
        match self {
            RocStructType::ByValue(struct_type) => struct_type.as_basic_type_enum(),
        }
    }
}

fn basic_type_from_record<'a, 'ctx>(
    env: &Env<'a, 'ctx, '_>,
    layout_interner: &mut STLayoutInterner<'a>,
    fields: &[InLayout<'_>],
) -> StructType<'ctx> {
    let mut field_types = AVec::with_capacity_in(fields.len(), env.arena);

    for field_layout in fields.iter() {
        let typ = basic_type_from_layout(env, layout_interner, *field_layout);

        field_types.push(typ);
    }

    env.context
        .struct_type(field_types.into_bump_slice(), false)
}

pub(crate) enum RocStruct<'ctx> {
    /// The roc struct should be passed by rvalue.
    ByValue(StructValue<'ctx>),
}

impl<'ctx> Into<BasicValueEnum<'ctx>> for RocStruct<'ctx> {
    fn into(self) -> BasicValueEnum<'ctx> {
        self.as_basic_value_enum()
    }
}

impl<'ctx> RocStruct<'ctx> {
    pub fn build<'a>(
        env: &Env<'a, 'ctx, '_>,
        layout_interner: &mut STLayoutInterner<'a>,
        scope: &Scope<'a, 'ctx>,
        sorted_fields: &[Symbol],
    ) -> Self {
        let struct_val = build_struct_value(env, layout_interner, scope, sorted_fields);
        RocStruct::ByValue(struct_val)
    }

    pub fn as_basic_value_enum(&self) -> BasicValueEnum<'ctx> {
        match self {
            RocStruct::ByValue(struct_val) => struct_val.as_basic_value_enum(),
        }
    }
}

fn build_struct_value<'a, 'ctx>(
    env: &Env<'a, 'ctx, '_>,
    layout_interner: &mut STLayoutInterner<'a>,
    scope: &Scope<'a, 'ctx>,
    sorted_fields: &[Symbol],
) -> StructValue<'ctx> {
    let ctx = env.context;

    // Determine types
    let num_fields = sorted_fields.len();
    let mut field_types = AVec::with_capacity_in(num_fields, env.arena);
    let mut field_vals = AVec::with_capacity_in(num_fields, env.arena);

    for symbol in sorted_fields.iter() {
        // Zero-sized fields have no runtime representation.
        // The layout of the struct expects them to be dropped!
        let (field_expr, field_layout) = scope.load_symbol_and_layout(symbol);
        if !layout_interner
            .get_repr(field_layout)
            .is_dropped_because_empty()
        {
            let field_type = basic_type_from_layout(env, layout_interner, field_layout);
            field_types.push(field_type);

            if layout_interner.is_passed_by_reference(field_layout) {
                let field_value = env.builder.new_build_load(
                    field_type,
                    field_expr.into_pointer_value(),
                    "load_tag_to_put_in_struct",
                );

                field_vals.push(field_value);
            } else {
                field_vals.push(field_expr);
            }
        }
    }

    // Create the struct_type
    let struct_type = ctx.struct_type(field_types.into_bump_slice(), false);

    // Insert field exprs into struct_val
    struct_from_fields(env, struct_type, field_vals.into_iter().enumerate())
}

pub fn struct_from_fields<'a, 'ctx, 'env, I>(
    env: &Env<'a, 'ctx, 'env>,
    struct_type: StructType<'ctx>,
    values: I,
) -> StructValue<'ctx>
where
    I: Iterator<Item = (usize, BasicValueEnum<'ctx>)>,
{
    let mut struct_value = struct_type.const_zero().into();

    // Insert field exprs into struct_val
    for (index, field_val) in values {
        let index: u32 = index as u32;

        struct_value = env
            .builder
            .build_insert_value(struct_value, field_val, index, "insert_record_field")
            .unwrap();
    }

    struct_value.into_struct_value()
}

pub fn load_at_index<'a, 'ctx>(
    env: &Env<'a, 'ctx, '_>,
    layout_interner: &mut STLayoutInterner<'a>,
    layout: InLayout<'a>,
    value: BasicValueEnum<'ctx>,
    index: u64,
) -> BasicValueEnum<'ctx> {
    let layout = if let LayoutRepr::LambdaSet(lambda_set) = layout_interner.get_repr(layout) {
        lambda_set.runtime_representation()
    } else {
        layout
    };

    // extract field from a record
    match (value, layout_interner.get_repr(layout)) {
        (BasicValueEnum::StructValue(argument), LayoutRepr::Struct(field_layouts)) => {
            debug_assert!(!field_layouts.is_empty());

            let field_value = env
                .builder
                .build_extract_value(
                    argument,
                    index as u32,
                    env.arena
                        .alloc(format!("struct_field_access_record_{}", index)),
                )
                .unwrap();

            let field_layout = field_layouts[index as usize];
            use_roc_value(
                env,
                layout_interner,
                field_layout,
                field_value,
                "struct_field_tag",
            )
        }
        (other, layout) => {
            // potential cause: indexing into an unwrapped 1-element record/tag?
            unreachable!(
                "can only index into struct layout\nValue: {:?}\nLayout: {:?}\nIndex: {:?}",
                other, layout, index
            )
        }
    }
}

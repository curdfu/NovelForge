<template>
  <el-form-item :label="label" :prop="prop">
    <el-input
      v-if="!isLongText"
      :model-value="modelValue"
      @update:modelValue="emit('update:modelValue', $event)"
      :placeholder="placeholder"
      clearable
    />
    <el-input
      v-else
      class="long-text-input"
      type="textarea"
      :model-value="modelValue"
      @update:modelValue="emit('update:modelValue', $event)"
      :placeholder="placeholder"
      :autosize="{ minRows: 4, maxRows: 18 }"
      clearable
    />
  </el-form-item>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { JSONSchema } from '@renderer/api/schema'

const props = defineProps<{
  modelValue: string | undefined
  label: string
  prop: string
  schema: JSONSchema
}>()

const emit = defineEmits(['update:modelValue'])

// 一个简单的启发式方法：如果描述、标题、字段名或当前内容表明它是长文本，则使用文本区域。
const isLongText = computed(() => {
  if (props.schema.minLength !== undefined && props.schema.minLength > 50) {
    return true
  }
  const currentValue = String(props.modelValue || '')
  if (currentValue.length > 80 || currentValue.includes('\n')) {
    return true
  }
  const description = props.schema.description?.toLowerCase() || ''
  const title = props.schema.title?.toLowerCase() || ''
  const prop = props.prop.toLowerCase()
  if (
    prop === 'overview'
    || prop === 'content'
    || prop.includes('description')
    || prop.includes('thinking')
    || prop.includes('summary')
    || prop.includes('analysis')
    || prop.includes('background')
    || prop.includes('relationship')
    || prop.includes('state')
    || prop.includes('definition')
    || prop.includes('hint')
    || prop.includes('guide')
    || prop.includes('note')
  ) return true
  return (
    description.includes('思考') ||
    description.includes('过程') ||
    description.includes('描述') ||
    description.includes('概述') ||
    description.includes('内容') ||
    description.includes('状态') ||
    description.includes('说明') ||
    title.includes('thinking') ||
    title.includes('描述') ||
    title.includes('概述') ||
    title.includes('内容')
  )
})

const placeholder = computed(() => {
  return props.schema.description || `请输入 ${props.label}`
})
</script>

<style scoped>
.long-text-input :deep(.el-textarea__inner) {
  line-height: 1.7;
  white-space: pre-wrap;
  word-break: break-word;
}
</style>

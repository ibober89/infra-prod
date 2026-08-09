from pathlib import Path


bench = Path("/home/frappe/frappe-bench")

pdf_preview = bench / "apps/drive/frontend/src/components/FileTypePreview/PDFPreview.vue"
list_view = bench / "apps/drive/frontend/src/components/ListView.vue"

pdf_text = pdf_preview.read_text(encoding="utf-8")
pdf_text = pdf_text.replace(
    '<div v-if="isMobile" class="flex flex-col gap-3 w-96 h-full justify-between grow">',
    '<div class="flex flex-col gap-3 w-full h-full justify-between grow">',
)
pdf_text = pdf_text.replace(
    'class="grow flex items-center justify-center border rounded-sm max-h-[70vh] overflow-auto"',
    'class="grow flex items-center justify-center border rounded-sm max-h-[80vh] max-w-[80vw] overflow-auto"',
)
pdf_text = pdf_text.replace(
    """  <embed
    v-else
    :src
    type="application/pdf"
    class="w-full h-full max-h-[80vh] max-w-[80vw] self-center"
  />
""",
    "",
)
pdf_text = pdf_text.replace(
    "import { breakpointsTailwind, useBreakpoints } from '@vueuse/core'\n",
    "",
)
pdf_text = pdf_text.replace(
    """const breakpoints = useBreakpoints(breakpointsTailwind)
const isMobile = breakpoints.smaller('sm')

""",
    "",
)
pdf_text = pdf_text.replace(
    "() => `/api/method/drive.api.files.get_file_content?entity_name=${props.previewEntity.name}`",
    "() => `/api/method/ecommerce.overrides.drive_patch.get_file_content_data?entity_name=${props.previewEntity.name}`",
)
pdf_text = pdf_text.replace(
    """  const task = PDFJS.getDocument(src.value)
""",
    """  const response = await fetch(src.value)
  const payload = await response.json()
  const binary = atob(payload.message?.data || payload.data)
  const data = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    data[i] = binary.charCodeAt(i)
  }
  const task = PDFJS.getDocument({ data })
""",
)
pdf_text = pdf_text.replace(
    "  if (isMobile.value) loadPDF()\n",
    "  loadPDF()\n",
)
pdf_preview.write_text(pdf_text, encoding="utf-8")

list_text = list_view.read_text(encoding="utf-8")
list_text = list_text.replace(
    "getRowRoute: (row) => getLink(row, false, false),",
    "getRowRoute: (row) => row.file_type === 'Link' ? null : getLink(row, false, false),",
)
list_view.write_text(list_text, encoding="utf-8")

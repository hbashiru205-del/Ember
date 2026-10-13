import streamlit as st
from pathlib import Path

st.set_page_config(page_title="Ember", page_icon="🔥", layout="wide", initial_sidebar_state="collapsed")
st.markdown(
    "<style>#MainMenu,header,footer{visibility:hidden}.block-container{padding:0!important;max-width:100%!important}</style>",
    unsafe_allow_html=True,
)
page = Path(__file__).parent / "index.html"
if hasattr(st, "iframe"):  # newer Streamlit
    st.iframe(page, height=1400)
else:  # older Streamlit
    import streamlit.components.v1 as components
    components.html(page.read_text(encoding="utf-8"), height=1400, scrolling=True)

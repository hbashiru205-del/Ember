import streamlit as st
import streamlit.components.v1 as components
from pathlib import Path

st.set_page_config(page_title="Ember", page_icon="🔥", layout="wide", initial_sidebar_state="collapsed")
st.markdown(
    "<style>#MainMenu,header,footer{visibility:hidden}.block-container{padding:0!important;max-width:100%!important}</style>",
    unsafe_allow_html=True,
)
html = Path(__file__).parent.joinpath("index.html").read_text(encoding="utf-8")
components.html(html, height=1400, scrolling=True)
